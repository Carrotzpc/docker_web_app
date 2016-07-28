FROM index.tenxcloud.com/docker_library/alpine:edge

# Install node.js by apk
RUN echo '@edge http://nl.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories
RUN apk update && apk upgrade
RUN apk add --no-cache nodejs-lts@edge

# If you have native dependencies, you'll need extra tools
# RUN apk add --no-cache make gcc g++ python

# Create app directory
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app

# Install app dependencies
COPY package.json /usr/src/app/
RUN npm install

# Bundle app source
COPY . /usr/src/app

# Expose port
EXPOSE 8080

CMD [ "npm", "start" ]
