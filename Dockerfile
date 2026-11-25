# CampusCrew – Docker deployment (optional alternative to bare-nginx)
# Build:  docker build -t campuscrew .
# Run:    docker run -d -p 80:80 campuscrew

FROM nginx:alpine

# Remove default nginx page
RUN rm /usr/share/nginx/html/index.html

# Copy app
COPY campuscrew_demo.html /usr/share/nginx/html/index.html

# Simple config: serve on port 80, gzip on
RUN printf 'server {\n\
    listen 80;\n\
    root /usr/share/nginx/html;\n\
    index index.html;\n\
    location / { try_files $uri /index.html; }\n\
    gzip on;\n\
    gzip_types text/html text/css application/javascript;\n\
}\n' > /etc/nginx/conf.d/default.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
