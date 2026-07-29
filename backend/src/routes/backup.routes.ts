import { Router } from 'express';
import { saveBackup, loadBackup } from '../controllers/backup.controller.js';
import { authenticateToken } from '../middleware/auth.middleware.js';

const router = Router();

router.post('/save', authenticateToken, saveBackup);
router.get('/load', authenticateToken, loadBackup);

export default router;
