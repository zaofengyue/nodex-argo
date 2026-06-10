FROM node:20-alpine
WORKDIR /app
COPY package.json index.js index.html ./
RUN apk add --no-cache curl unzip
CMD ["node", "index.js"]
