FROM nginx:1.31-alpine

RUN apk add --no-cache bash gettext

COPY nginx.conf.template /etc/nginx/templates/nginx.conf.template
COPY docker-entrypoint.sh /docker-entrypoint.sh
COPY mcp-notifications.js /etc/nginx/mcp-notifications.js

RUN chmod +x /docker-entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/docker-entrypoint.sh"]
