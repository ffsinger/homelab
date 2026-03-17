FROM node:alpine AS builder

# Install git
RUN apk add --no-cache git

# Clone the repository
WORKDIR /app
RUN git clone https://github.com/Gnathonic/mokuro-reader.git .

# Install dependencies
RUN npm install

# Install SvelteKit Node adapter
RUN npm install -D @sveltejs/adapter-node

# Configure SvelteKit to use Node adapter
RUN sed -i "s|import adapter from '@sveltejs/adapter-auto';|import adapter from '@sveltejs/adapter-node';|" svelte.config.js

# Build the application
RUN npm run build

# Production stage
FROM node:alpine

WORKDIR /app

# Copy built application from builder
COPY --from=builder /app /app

# Expose the port
EXPOSE 3000

# Run the SvelteKit Node server
CMD ["node", "build"]
