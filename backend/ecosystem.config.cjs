module.exports = {
  apps: [
    {
      name: "dolsyx-backend",
      script: "dist/index.js",
      instances: "max",
      exec_mode: "cluster",
      watch: false,
      max_memory_restart: "1G",
      env: {
        NODE_ENV: "production",
      },
      env_development: {
        NODE_ENV: "development",
      },
    },
  ],
};
