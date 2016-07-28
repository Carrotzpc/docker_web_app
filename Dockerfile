FROM index.tenxcloud.com/docker_library/alpine:edge

# Create app directory and bundle app source
RUN mkdir -p /usr/src/app
WORKDIR /usr/src/app
COPY . /usr/src/app

# Install node.js and app dependencies
RUN echo '@edge http://nl.alpinelinux.org/alpine/edge/main' >> /etc/apk/repositories \
  && apk update && apk upgrade \
  && apk add --no-cache nodejs-lts@edge \
  && npm install \
  && npm uninstall -g npm \
  && rm -rf /tmp/* \
  && rm -rf /root/.npm/
  
# Expose port
EXPOSE 8080

CMD [ "node", "app.js" ]
