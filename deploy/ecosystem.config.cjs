module.exports = { apps: [{
  name: "everframe-web",
  script: "/var/www/everframe/current/scripts/native-service.sh",
  interpreter: "/bin/bash",
  cwd: "/var/www/everframe/current",
  autorestart: true,
  max_memory_restart: "256M",
  time: true,
  out_file: "/var/www/everframe/shared/logs/website.log",
  error_file: "/var/www/everframe/shared/logs/website-error.log"
}] };
