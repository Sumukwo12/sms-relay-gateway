# Production image for the verification web page (Next.js standalone server).
#
#   docker build -t sms-frontend ./frontend
#
# NEXT_PUBLIC_API_URL is inlined at build time. The default "" makes the page
# call the API on its own origin (/api/...), which is how deploy/ serves it:
# one hostname, with the reverse proxy sending /api, /v1 and /phone to the
# backend and everything else here.
FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --no-audit --no-fund

FROM node:22-alpine AS builder
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG NEXT_PUBLIC_API_URL=""
ENV NEXT_PUBLIC_API_URL=$NEXT_PUBLIC_API_URL NEXT_TELEMETRY_DISABLED=1
RUN npm run build

FROM node:22-alpine
WORKDIR /app
ENV NODE_ENV=production NEXT_TELEMETRY_DISABLED=1 PORT=3000 HOSTNAME=0.0.0.0
COPY --from=builder --chown=node /app/.next/standalone ./
COPY --from=builder --chown=node /app/.next/static ./.next/static
USER node
EXPOSE 3000
CMD ["node", "server.js"]
