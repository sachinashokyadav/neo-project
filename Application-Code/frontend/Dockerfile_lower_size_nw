# ==============================
# Stage 1: Build frontend
# ==============================
FROM node:16-alpine AS build

WORKDIR /usr/src/app

# Copy only dependency files and install dependencies
COPY package*.json ./
RUN npm ci

# Copy source code and build production files
COPY . .
RUN npm run build

# ==============================
# Stage 2: Serve with Nginx
# ==============================
FROM nginx:alpine

# Copy production build to nginx html folder
COPY --from=build /usr/src/app/build /usr/share/nginx/html

# Expose port 80 for the app
EXPOSE 80

# Run Nginx
CMD ["nginx", "-g", "daemon off;"]
