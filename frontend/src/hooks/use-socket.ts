"use client";

import { useSocketContext } from "@/context/socket-context";

export const useSocket = (_token?: string | null) => {
  return useSocketContext();
};
