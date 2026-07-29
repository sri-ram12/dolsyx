'use client';

/**
 * useE2EEInit — A hook that auto-initializes E2EE when a user is authenticated.
 * Drop this into any page that needs encryption (e.g., the chat page).
 * 
 * Usage:
 *   const { isInitialized, isInitializing, error } = useE2EEInit();
 */

import { useEffect } from 'react';
import { useAuth } from '@/context/auth-context';
import { useE2EE } from '@/context/e2ee-context';

export function useE2EEInit() {
  const { user, token, isAuthenticated } = useAuth();
  const { isInitialized, isInitializing, initializeE2EE, error } = useE2EE();

  useEffect(() => {
    if (isAuthenticated && user && token && !isInitialized && !isInitializing) {
      initializeE2EE(user.id, token).catch(console.error);
    }
  }, [isAuthenticated, user, token, isInitialized, isInitializing, initializeE2EE]);

  return { isInitialized, isInitializing, error };
}
