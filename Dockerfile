FROM nginx:1.27-alpine

# On retire la config par défaut d'Nginx et on copie le site statique
RUN rm -rf /usr/share/nginx/html/*
COPY site/index.html /usr/share/nginx/html/index.html
COPY site/style.css /usr/share/nginx/html/style.css

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s CMD wget -q -O- http://localhost/ || exit 1
