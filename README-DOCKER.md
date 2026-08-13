# 🐳 DOLSYX Docker Deployment & Orchestration Guide

This guide explains how to build, run, and orchestrate the entire **DOLSYX** platform (PostgreSQL Database, Node.js Backend, and Next.js Web App) using Docker and Docker Compose.

---

## 🚀 Quick Start (One-Command Launch)

To build and run all services in production mode locally:

```bash
docker compose up --build -d
```

This will automatically start:
1. **PostgreSQL Database** on `localhost:5432`
2. **Node.js Express REST & WebSocket Backend** on `localhost:5000`
3. **Next.js 14 Web Frontend** on `localhost:3000`

---

## 🛠️ Management Commands

### Check Container Status
```bash
docker compose ps
```

### View Live Logs
```bash
docker compose logs -f
```

### Stop All Services
```bash
docker compose down
```

### Reset & Wipe Data Volumes (Clean Slate)
```bash
docker compose down -v
```

---

## 📁 Docker Structure

- [`docker-compose.yml`](file:///c:/Users/chand/OneDrive/Desktop/DOLSYX/docker-compose.yml): Main multi-container orchestration.
- [`backend/Dockerfile`](file:///c:/Users/chand/OneDrive/Desktop/DOLSYX/backend/Dockerfile): Production Node.js + Prisma image.
- [`frontend/Dockerfile`](file:///c:/Users/chand/OneDrive/Desktop/DOLSYX/frontend/Dockerfile): Standalone Next.js 14 production build.
- [`backend/.dockerignore`](file:///c:/Users/chand/OneDrive/Desktop/DOLSYX/backend/.dockerignore): Optimized backend build ignores.
- [`frontend/.dockerignore`](file:///c:/Users/chand/OneDrive/Desktop/DOLSYX/frontend/.dockerignore): Optimized frontend build ignores.
