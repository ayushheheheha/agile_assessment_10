FROM nginx:alpine

# Dashboard
COPY index.html /usr/share/nginx/html/index.html

# Health endpoint used by the Kubernetes readiness probe
RUN echo "OK" > /usr/share/nginx/html/healthz

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]