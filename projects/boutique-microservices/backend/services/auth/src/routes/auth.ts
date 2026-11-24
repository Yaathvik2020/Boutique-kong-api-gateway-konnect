import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../database/connection';

// Login tokens are signed JWTs (HS256) with the shared JWT_SECRET (Kubernetes Secret
// boutique-secrets, from Secrets Manager boutique/<env>/app). user-service verifies the
// same access tokens with the same secret.
//   access token : { userId, role, typ: "access"  }  valid ACCESS_TTL  (default 1h)
//   refresh token: { userId,       typ: "refresh" }  valid REFRESH_TTL (default 7d), JWT_REFRESH_SECRET
// No state is kept in memory, so every pod/replica gives the same answer.
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  // Fail fast instead of signing tokens with a guessable default.
  throw new Error('JWT_SECRET must be set (at least 32 characters)');
}
// Refresh tokens use their own secret when it is set (boutique-secrets JWT_REFRESH_SECRET), so a
// leaked access-token secret cannot mint long-lived refresh tokens.
const REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || JWT_SECRET;
const ACCESS_TTL = process.env.JWT_ACCESS_TTL || '1h';
const REFRESH_TTL = process.env.JWT_REFRESH_TTL || '7d';
const ISSUER = 'boutique-auth';

interface TokenClaims {
  userId: string;
  role?: string;
  typ: 'access' | 'refresh';
}

const signAccess = (user: { id: string; role: string }) =>
  jwt.sign({ userId: user.id, role: user.role, typ: 'access' }, JWT_SECRET, {
    expiresIn: ACCESS_TTL,
    issuer: ISSUER,
    algorithm: 'HS256',
  } as jwt.SignOptions);

const signRefresh = (user: { id: string }) =>
  jwt.sign({ userId: user.id, typ: 'refresh' }, REFRESH_SECRET, {
    expiresIn: REFRESH_TTL,
    issuer: ISSUER,
    algorithm: 'HS256',
  } as jwt.SignOptions);

const verify = (token: string, typ: TokenClaims['typ']): TokenClaims | null => {
  try {
    const secret = typ === 'refresh' ? REFRESH_SECRET : JWT_SECRET;
    const claims = jwt.verify(token, secret, { issuer: ISSUER, algorithms: ['HS256'] }) as TokenClaims;
    return claims.typ === typ && claims.userId ? claims : null;
  } catch {
    return null;
  }
};

const publicUser = (u: any) => ({
  id: u.id,
  email: u.email,
  firstName: u.first_name,
  lastName: u.last_name,
  role: u.role,
  createdAt: u.created_at,
  updatedAt: u.updated_at,
});

const router = express.Router();

router.post('/register', async (req, res) => {
  try {
    const { email, password, firstName, lastName } = req.body || {};
    if (!email || !password || typeof password !== 'string' || password.length < 8) {
      return res.status(400).json({ error: 'Email and a password of at least 8 characters are required' });
    }

    const existingUser = await query('SELECT id FROM users WHERE email = $1', [email]);
    if (existingUser.rows.length > 0) {
      return res.status(409).json({ error: 'User already exists' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);
    const result = await query(
      'INSERT INTO users (email, password_hash, first_name, last_name, role) VALUES ($1, $2, $3, $4, $5) RETURNING id, email, first_name, last_name, role, created_at, updated_at',
      [email, hashedPassword, firstName, lastName, 'customer']
    );
    const user = result.rows[0];

    res.status(201).json({
      user: publicUser(user),
      token: signAccess(user),
      refreshToken: signRefresh(user),
      message: 'Registration successful',
    });
  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Registration failed' });
  }
});

router.post('/login', async (req, res) => {
  try {
    const { email, password } = req.body || {};
    if (!email || !password) {
      return res.status(400).json({ error: 'Email and password are required' });
    }

    const result = await query(
      'SELECT id, email, password_hash, first_name, last_name, role, created_at, updated_at FROM users WHERE email = $1',
      [email]
    );
    const user = result.rows[0];
    // Same answer for "no such user" and "wrong password": don't reveal which emails exist.
    if (!user || !(await bcrypt.compare(password, user.password_hash))) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    res.json({
      user: publicUser(user),
      token: signAccess(user),
      refreshToken: signRefresh(user),
      message: 'Login successful',
    });
  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Login failed' });
  }
});

// The frontend calls this when an API answers 401: new access token from the refresh token.
router.post('/refresh', async (req, res) => {
  const claims = verify(req.body?.refreshToken || '', 'refresh');
  if (!claims) {
    return res.status(401).json({ error: 'Invalid or expired refresh token' });
  }
  try {
    const result = await query('SELECT id, role FROM users WHERE id = $1', [claims.userId]);
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'User not found' });
    }
    res.json({ token: signAccess(result.rows[0]) });
  } catch (error) {
    console.error('Refresh error:', error);
    res.status(500).json({ error: 'Refresh failed' });
  }
});

// Tokens are stateless: logging out means the browser deletes them (the frontend does).
router.post('/logout', (_req, res) => {
  res.json({ message: 'Logged out successfully' });
});

router.get('/me', async (req, res) => {
  const header = req.headers.authorization || '';
  const claims = header.startsWith('Bearer ') ? verify(header.slice(7), 'access') : null;
  if (!claims) {
    return res.status(401).json({ error: 'Not logged in' });
  }

  try {
    const result = await query(
      'SELECT id, email, first_name, last_name, role, created_at, updated_at FROM users WHERE id = $1',
      [claims.userId]
    );
    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'User not found' });
    }
    const user = publicUser(result.rows[0]);
    res.json({ id: user.id, email: user.email, firstName: user.firstName, lastName: user.lastName, role: user.role });
  } catch (error) {
    console.error('Get user error:', error);
    res.status(500).json({ error: 'Failed to get user' });
  }
});

export { router as authRoutes };
