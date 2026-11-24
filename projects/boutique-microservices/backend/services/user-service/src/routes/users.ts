import express from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { query } from '../database/connection';
import { UserProfile, Address, ServiceResponse } from '../types';

const router = express.Router();
// Same secret as the auth service (Kubernetes Secret boutique-secrets, key JWT_SECRET).
// No default: a guessable fallback would let anyone sign tokens.
const JWT_SECRET = process.env.JWT_SECRET;
if (!JWT_SECRET || JWT_SECRET.length < 32) {
  throw new Error('JWT_SECRET must be set (at least 32 characters)');
}

// Accept only ACCESS tokens issued by the auth service (not refresh tokens).
const verifyAccess = (token: string): { userId: string } | null => {
  try {
    const claims = jwt.verify(token, JWT_SECRET, { issuer: 'boutique-auth', algorithms: ['HS256'] }) as any;
    return claims && claims.typ === 'access' && claims.userId ? claims : null;
  } catch {
    return null;
  }
};
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'your-refresh-secret';

router.get('/profile', async (req, res) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }

    const decoded = verifyAccess(token);
    if (!decoded) {
      return res.status(401).json({ success: false, error: 'Invalid or expired token' });
    }
    
    const result = await query('SELECT id, email, first_name, last_name, role, created_at, updated_at FROM users WHERE id = $1', [decoded.userId]);
    
    if (result.rows.length === 0) {
      return res.status(401).json({ success: false, error: 'Invalid token' });
    }

    const user = result.rows[0];
    
    const preferencesResult = await query('SELECT * FROM user_preferences WHERE user_id = $1', [user.id]);
    const addressesResult = await query('SELECT * FROM addresses WHERE user_id = $1', [user.id]);

    const response: ServiceResponse<UserProfile> = {
      success: true,
      data: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        role: user.role,
        preferences: preferencesResult.rows[0] || {
          currency: 'USD',
          language: 'en',
          newsletter: true,
          promotions: true
        },
        addresses: addressesResult.rows,
        createdAt: user.created_at,
        updatedAt: user.updated_at
      }
    };
    
    res.json(response);
  } catch (error) {
    console.error('Get profile error:', error);
    res.status(500).json({ success: false, error: 'Failed to get profile' });
  }
});

router.put('/profile', async (req, res) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }

    const decoded = verifyAccess(token);
    if (!decoded) {
      return res.status(401).json({ success: false, error: 'Invalid or expired token' });
    }
    const { firstName, lastName } = req.body;

    await query(
      'UPDATE users SET first_name = $1, last_name = $2, updated_at = CURRENT_TIMESTAMP WHERE id = $3',
      [firstName, lastName, decoded.userId]
    );

    const result = await query('SELECT id, email, first_name, last_name, role, created_at, updated_at FROM users WHERE id = $1', [decoded.userId]);
    const user = result.rows[0];

    const response: ServiceResponse<UserProfile> = {
      success: true,
      data: {
        id: user.id,
        email: user.email,
        firstName: user.first_name,
        lastName: user.last_name,
        role: user.role,
        preferences: {
          currency: 'USD',
          language: 'en',
          newsletter: true,
          promotions: true
        },
        addresses: [],
        createdAt: user.created_at,
        updatedAt: user.updated_at
      }
    };
    
    res.json(response);
  } catch (error) {
    console.error('Update profile error:', error);
    res.status(500).json({ success: false, error: 'Failed to update profile' });
  }
});

router.post('/addresses', async (req, res) => {
  try {
    const token = req.headers.authorization?.replace('Bearer ', '');
    
    if (!token) {
      return res.status(401).json({ success: false, error: 'No token provided' });
    }

    const decoded = verifyAccess(token);
    if (!decoded) {
      return res.status(401).json({ success: false, error: 'Invalid or expired token' });
    }
    const { street, city, state, zipCode, country, isDefault } = req.body;

    const result = await query(
      'INSERT INTO addresses (user_id, street, city, state, zip_code, country, is_default) VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *',
      [decoded.userId, street, city, state, zipCode, country, isDefault]
    );

    const response: ServiceResponse<Address> = {
      success: true,
      data: result.rows[0]
    };
    
    res.status(201).json(response);
  } catch (error) {
    console.error('Add address error:', error);
    res.status(500).json({ success: false, error: 'Failed to add address' });
  }
});

export { router as userRoutes };
