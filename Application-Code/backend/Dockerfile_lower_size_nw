# ==============================
# Stage 1: Dependencies
# ==============================
FROM node:16-alpine AS deps

WORKDIR /usr/src/app

# Install only production dependencies
COPY package*.json ./
RUN npm ci --only=production

# ==============================
# Stage 2: Runtime
# ==============================
FROM node:16-alpine

WORKDIR /usr/src/app

# Copy installed dependencies from build stage
COPY --from=deps /usr/src/app/node_modules ./node_modules

# Copy application source
COPY . .

# Expose app port
EXPOSE 8080

# Run app
CMD ["node", "index.js"]
