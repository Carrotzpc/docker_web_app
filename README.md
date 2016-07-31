## 高质量Node.js微服务的编写和部署
![node.js+docker](https://oayex8dmm.qnssl.com/image/others/header.png)

微服务架构是一种构造应用程序的替代性方法。应用程序被分解为更小、完全独立的组件，这使得它们拥有更高的敏捷性、可伸缩性和可用性。一个复杂的应用被拆分为若干微服务，微服务更需要一种成熟的交付能力。持续集成、部署和全自动测试都必不可少。编写代码的开发人员必须负责代码的生产部署。构建和部署链需要重大更改，以便为微服务环境提供正确的关注点分离。后续我们会聊一下如何在时速云平台上集成 DevOps。

![microservice](https://oayex8dmm.qnssl.com/image/others/microservice.png)

>Node.js® is a JavaScript runtime built on Chrome's V8 JavaScript engine. Node.js uses an event-driven, non-blocking I/O model that makes it lightweight and efficient. Node.js' package ecosystem, npm, is the largest ecosystem of open source libraries in the world.    --- https://nodejs.org

Node.js 是构建微服务的利器，为什么这么说呢，我们先看下 Node.js 有哪些优势：

1. Node.js 采用事件驱动、异步编程，为网络服务而设计
2. Node.js 非阻塞模式的IO处理给 Node.js 带来在相对低系统资源耗用下的高性能与出众的负载能力，非常适合用作依赖其它IO资源的中间层服务
3. Node.js轻量高效，可以认为是数据密集型分布式部署环境下的实时应用系统的完美解决方案。

这些优势正好与微服务的优势：敏捷性、可伸缩性和可用性相契合（捂脸笑），再看下 Node.js 的缺点：

1. 单进程，单线程，只支持单核CPU，不能充分的利用多核CPU服务器。一旦这个进程 down 了，那么整个 web 服务就 down 了
2. 异步编程，callback 回调地狱

第一个缺点可以通过启动多个实例来实现CPU充分利用以及负载均衡，话说这不是 K8s 的原生功能吗。第二个缺点更不是事儿，现在可以通过 `generator`、`promise`等来写同步代码，爽的不要不要的。

下面我们主要从 Docker 和 Node.js 出发聊一下高质量Node.js微服务的编写和部署：

1. Node.js 异步流程控制：generator 与 promise
2. Express、Koa 的异常处理
3. 如何编写 Dockerfile
4. 微服务部署及 DevOps 集成



#### 1 Node.js 异步流程控制：Generator 与 Promise
Node.js 的设计初衷为了性能而异步，现在已经可以写同步的代码了，你造吗？目前 Node.js 的`LTS`版本早就支持了`Generator`, `Promise`这两个特性，也有许多优秀的第三方库 bluebird、q 这样的模块支持的也非常好，性能甚至比原生的还好，可以用 bluebird 替换 Node.js 原生的 Promise:
```
global.Promise = require('bluebird')
```
blurbird 的性能是 V8 里内置的 Promise 3 倍左右（bluebird 的优化方式见 https://github.com/petkaantonov/bluebird/wiki/Optimization-killers ）。
##### 1.1 ES2015 Generator
>Generators are functions which can be exited and later re-entered. Their context (variable bindings) will be saved across re-entrances.   --- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/function*

generator 就像一个取号机，你可以通过取一张票来向机器请求一个号码。你接收了你的号码，但是机器不会自动为你提供下一个。换句话说，取票机“暂停”直到有人请求另一个号码(`next()`)，此时它才会向后运行。下面我们看一个简单的示例：
```javascript
function* idMaker(){
  var index = 0
  while(index < 3)
    yield index++
}

var gen = idMaker()

gen.next() // {value: 0, done: false}
gen.next() // {value: 1, done: false}
gen.next() // {value: 2, done: false}
gen.next() // {value: undefined, done: true}
// ...
```
![generator_sample](https://oayex8dmm.qnssl.com/image/others/generator_sample_1.jpg)

从上面的代码的输出可以看出:

1. generator 函数的定义，是通过 `function *(){}` 实现的
2. 对 generator 函数的调用返回的实际是一个遍历器，随后代码通过使用遍历器的 `next()` 方法来获得函数的输出
3. 通过使用`yield`语句来中断 generator 函数的运行，并且可以返回一个中间结果
4. 每次调用`next()`方法，generator 函数将执行到下一个`yield`语句或者是`return`语句。
 
下面我们就对上面代码的每次next调用进行一个详细的解释：

1. 第1次调用`next()`方法的时候，函数执行到第一次循环的`yield index++`语句停了下来，并且返回了`0`这个`value`，随同`value`返回的`done`属性表明 generator 函数的运行还没有结束
2. 第2次调用`next()`方法的时候，函数执行到第二循环的`yield index++`语句停了下来，并且返回了`1`这个`value`，随同`value`返回的`done`属性表明 generator 函数的运行还没有结束
3. ... ...
4. 第4次调用`next()`方法的时候，由于循环已经结束了，所以函数调用立即返回，`done`属性表明 generator 函数已经结束运行，`value`是`undefined`的，因为这次调用并没有执行任何语句

PS: 如果在 generator 函数内部需要调用另外一个 generator 函数，那么对目标函数的调用就需要使用`yield*`。

##### 1.2 ES2015 Promise
> The Promise object is used for asynchronous computations. A Promise represents an operation that hasn't completed yet, but is expected in the future.   --- https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Global_Objects/Promise

所谓 Promise，就是一个对象，用来传递异步操作的消息。它代表了某个未来才会知道结果的事件（通常是一个异步操作），并且这个事件提供统一的 API，可供进一步处理。

![promise](https://oayex8dmm.qnssl.com/image/others/promise.png)

一个 Promise 一般有3种状态：
1. `pending`: 初始状态, 不是`fulfilled`，也不是`rejected`.
2. `fulfilled`: 操作成功完成.
3. `rejected`: 操作失败.

一个 Promise 的生命周期如下图：

![promises_full](https://oayex8dmm.qnssl.com/image/others/promises_full.png)

下面我们看一段具体代码：
```javascript
function asyncFunction() {
  return new Promise(function (resolve, reject) {
    setTimeout(function () {
      resolve('Async Hello world')
    }, 16)
  })
}

asyncFunction().then(function (value) {
  console.log(value)  // => 'Async Hello world'
}).catch(function (error) {
  console.log(error)
})
```
`asyncFunction` 这个函数会返回 Promise 对象， 对于这个 Promise 对象，我们调用它的`then` 方法来设置`resolve`后的回调函数，`catch`方法来设置发生错误时的回调函数。

该 Promise 对象会在`setTimeout`之后的`16ms`时被`resolve`, 这时`then`的回调函数会被调用，并输出 'Async Hello world' 。

在这种情况下`catch`的回调函数并不会被执行（因为 Promise 返回了`resolve`）， 不过如果运行环境没有提供 setTimeout 函数的话，那么上面代码在执行中就会产生异常，在 catch 中设置的回调函数就会被执行。

![promises_reject](https://oayex8dmm.qnssl.com/image/others/promises_reject.png)

##### 小结
如果是编写一个 SDK 或 API，推荐使用传统的 callback 或者 Promise，不使用 generator 的原因是：
* generator 的出现不是为了解决异步问题
* 使用 generator 是会传染的，当你尝试`yield`一下的时候，它要求你也必须在一个 generator function 内

（[《如何用 Node.js 编写一个 API 客户端》](https://cnodejs.org/topic/572d68b1afd3b34a17ff40f0)@leizongmin）

由此看来学习 Promise 是水到渠成的事情。

#### 2 Express、Koa 的异常处理
![exception_handle](https://oayex8dmm.qnssl.com/image/others/exception_handle.jpg)

一个友好的错误处理机制应该满足三个条件:

1. 对于引发异常的用户，返回 500 页面
2. 其他用户不受影响，可以正常访问
3. 不影响整个进程的正常运行

下面我们就以这三个条件为原则，具体介绍下 Express、Koa 中的异常处理：

##### 2.1 Express 异常处理
在 Express 中有一个内置的错误处理中间件，这个中间件会处理任何遇到的错误。如果你在 Express 中传递了一个错误给`next()`，而没有自己定义的错误处理函数处理这个错误，这个错误就会被 Express 默认的错误处理函数捕获并处理，而且会把错误的堆栈信息返回到客户端，这样的错误处理是非常不友好的，还好我们可以通过设置`NODE_ENV`环境变量为`production`，这样 Express 就会在生产环境模式下运行应用，生产环境模式下 Express 不会把错误的堆栈信息返回到客户端。

在 Express 项目中可以定义一个错误处理的中间件用来替换 Express 默认的错误处理函数：
```javascript
app.use(errorHandler)
function errorHandler(err, req, res, next) {
  if (res.headersSent) {
    return next(err)
  }
  res.status(500)
  switch(req.accepts(['html', 'json'])) {
    case 'html':
      res.render('error', { error: err })
      break
    default:
      res.send('500 Internal Server Error')
  }
}
```
在所有其他`app.use()`以及路由之后引入以上代码，可以满足以上三个友好错误处理条件，是一种非常友好的错误处理机制。
##### 2.2 Koa 异常处理
我们以`Koa 1.x`为例，看代码：
```javascript
app.use(function *(next) {
  try {
    yield next
  } catch (err) {
    this.status = err.status || 500
    this.body = err
    this.app.emit('error', err, this)
  }
})
```
把上面的代码放在所有`app.use()`函数前面，这样基本上所有的同步错误均会被 `try{} catch(err){}` 捕获到了，具体原理大家可以了解下 Koa 中间件的机制。
##### 2.3 未捕获的异常 `uncaughtException`
上面的两种异常处理方法，只能捕获同步错误，而异步代码产生的错误才是致命的，`uncaughtException`错误会导致当前的所有用户连接都被中断，甚至不能返回一个正常的`HTTP` 错误码，用户只能等到浏览器超时才能看到一个`no data received`错误。

这是一种非常野蛮粗暴的异常处理机制，任何线上服务都不应该因为`uncaughtException` 导致服务器崩溃。在Node.js 我们可以通过以下代码捕获 `uncaughtException`错误：
```javascript
process.on('uncaughtException', function (err) {
  console.error('Unexpected exception: ' + err)
  console.error('Unexpected exception stack: ' + err.stack)
  // Do something here: 
  // Such as send a email to admin
  // process.exit(1)
})
```
捕获`uncaughtException`后，Node.js 的进程就不会退出，但是当 Node.js 抛出 uncaughtException 异常时就会丢失当前环境的堆栈，导致 Node.js 不能正常进行内存回收。也就是说，每一次、`uncaughtException` 都有可能导致内存泄露。既然如此，退而求其次，我们可以在满足前两个条件的情况下退出进程以便重启服务。当然还可以利用`domain`模块做更细致的异常处理，这里就不做介绍了。

#### 3 如何编写 Dockerfile

##### 3.1 基础镜像选择
我们先选用 Node.js 官方推荐的`node:argon`官方`LTS`版本最新镜像，镜像大小为`656.9 MB`(解压后大小，下文提到的镜像大小没有特殊说明的均指解压后的大小)

>The first thing we need to do is define from what image we want to build from. Here we will use the latest LTS (long term support) version `argon` of `node` available from the Docker Hub     --- https://nodejs.org/en/docs/guides/nodejs-docker-webapp/

我们事先写好了两个文件`package.json`, `app.js`:
```json
{
  "name": "docker_web_app",
  "version": "1.0.0",
  "description": "Node.js on Docker",
  "author": "Zhangpc <zhangpc@tenxcloud.com>",
  "main": "app.js",
  "scripts": {
    "start": "node app.js"
  },
  "dependencies": {
    "express": "^4.13.3"
  }
}
```

```javascript
// app.js
'use strict';

const express = require('express')

// Constants
const PORT = 8080

// App
const app = express()
app.get('/', function (req, res) {
  res.send('Hello world\n')
})

app.listen(PORT)
console.log('Running on http://localhost:' + PORT)
```

下面开始编写 Dockerfile，由于直接从 Dockerhub 拉取镜像速度较慢，我们选用时速云的docker官方镜像 [docker_library/node](https://hub.tenxcloud.com/repos/docker_library/node)，这些官方镜像都是与 Dockerhub 实时同步的:
```
# Dockerfile.argon
FROM index.tenxcloud.com/docker_library/node:argon

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
```
执行以下命令进行构建：
```bash
docker build -t zhangpc/docker_web_app:argon .
```
最终得到的镜像大小是`660.3 MB`，体积略大，Docker 容器的优势是轻量和可移植，所以承载它的操作系统即基础镜像也应该迎合这个特性，于是我想到了`Alpine Linux`，一个面向安全的，轻量的 Linux 发行版，基于 `musl` `libc`和`busybox`。

下面我们使用`alpine:edge`作为基础镜像，镜像大小为`4.799 MB`：
```
# Dockerfile.alpine
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

# If your project depends on many package, you can use cnpm instead of npm
# RUN npm install cnpm -g --registry=https://registry.npm.taobao.org
# RUN cnpm install

# Install app dependencies
COPY package.json /usr/src/app/
RUN npm install

# Bundle app source
COPY . /usr/src/app

# Expose port
EXPOSE 8080

CMD [ "npm", "start" ]
```
执行以下命令进行构建：
```bash
docker build -t zhangpc/docker_web_app:alpine .
```
最终得到的镜像大小是`31.51 MB`，足足缩小了20倍，运行两个镜像均测试通过。
##### 3.2 还有优化的空间吗？
首先，大小上还是可以优化的，我们知道 Dockerfile 的每条指令都会将结果提交为新的镜像，下一条指令将会基于上一步指令的镜像的基础上构建，所以如果我们要想清除构建过程中产生的缓存，就得保证产生缓存的命令和清除缓存的命令在同一条 Dockerfile 指令中，因此修改 Dockerfile 如下：
```
# Dockerfile.alpine-mini
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
```
执行以下命令进行构建：
```bash
docker build -t zhangpc/docker_web_app:alpine .
```
最终得到的镜像大小是`21.47 MB`，缩小了10M。

其次，我们发现在构建过程中有一些依赖是基本不变的，例如安装 Node.js 以及项目依赖，我们可以把这些不变的依赖集成在基础镜像中，这样可以大幅提升构建速度，基本上是秒级构建。当然也可以把这些基本不变的指令集中在 Dockerfile 的前面部分，并保持前面部分不变，这样就可以利用缓存提升构建速度。

最后，如果使用了 Express 框架，在构建生产环境镜像时可以设置`NODE_ENV`环境变量为`production`，可以大幅提升应用的性能，还有其他诸多好处，下面会有介绍。 
##### 小结
![docker_web_app_size](https://oayex8dmm.qnssl.com/image/others/docker_web_app_size_new.jpg)

我们构建的三个镜像大小对比见上图，镜像的大小越小，发布的时候越快捷，而且可以提高安全性，因为更少的代码和程序在容器中意味着更小的攻击面。使用`node:argon`作为基础镜像构建出的镜像（tag 为 argon）压缩后的大小大概为`254 MB`，也不是很大，如果对`Alpine Linux`心存顾虑的童鞋可以选用 Node.js 官方推荐的`node:argon`作为基础镜像构建微服务。

#### 4 微服务部署及 devops 集成
部署微服务时有一个原则：一个容器中只放一个服务，可以使用stack 编排把各个微服务组合成一个完整的应用：

![devops_stack](https://oayex8dmm.qnssl.com/image/others/devops_stack.png)

##### 4.1 Dokcer 环境微服务部署
安装好 Docker 环境后，直接运行我们构建好的容器即可：
```
docker run -d --restart=always -p 8080:8080 --name docker_web_app_alpine zhangpc/docker_web_app:alpine
```
##### 4.2 使用时速云平台集成 DevOps
时速云目前支持github、gitlab、bitbucket、coding 等代码仓库，并已实现完全由API接入授权、webhook等，只要你开发时使用的是这些代码仓库，都可以接入时速云的 CI/CD 服务：

![tenxcloud_devpos](https://oayex8dmm.qnssl.com/image/others/tenxcloud_devpos_1.jpg)

下面我们简单介绍下接入流程：

1. 创建项目，参考文档 http://doc.tenxcloud.com/doc/v1/ci/project-add.html
2. 开启CI

![devops_ci](https://oayex8dmm.qnssl.com/image/others/devops_ci.png)

3. 更改代码并提交，项目自动构建

![devops_ci_build](https://oayex8dmm.qnssl.com/image/others/devops_ci_build.png)

4. 用构建出来的镜像（`tag`为`master`）创建一个容器

![devops_image](https://oayex8dmm.qnssl.com/image/others/devops_image.png)

![devops_deploy](https://oayex8dmm.qnssl.com/image/others/devops_deploy.png)

5. 开启CD，并绑定刚刚创建的容器

![devops_cd](https://oayex8dmm.qnssl.com/image/others/devops_cd.png)

6. 更改代码，测试 DevOps

![devops_edit_code](https://oayex8dmm.qnssl.com/image/others/devops_edit_code.png)

![devops_ci_build_2](https://oayex8dmm.qnssl.com/image/others/devops_ci_build_2.png)

![devops_ci_build_2](https://oayex8dmm.qnssl.com/image/others/devops_ci_build_2.png)

![devops_deploy_2](https://oayex8dmm.qnssl.com/image/others/devops_deploy_2.png)
 
我们可以看到代码更改已经经过构建（CI）、部署(CD)体现在了容器上。

#### 参考资料
* 《微服务、SOA 和 API：是敌是友？》http://www.ibm.com/developerworks/cn/websphere/library/techarticles/1601_clark-trs/1601_clark.html
* 《解析微服务架构(一)：什么是微服务》https://www.ibm.com/developerworks/community/blogs/3302cc3b-074e-44da-90b1-5055f1dc0d9c/entry/%E8%A7%A3%E6%9E%90%E5%BE%AE%E6%9C%8D%E5%8A%A1%E6%9E%B6%E6%9E%84_%E4%B8%80_%E4%BB%80%E4%B9%88%E6%98%AF%E5%BE%AE%E6%9C%8D%E5%8A%A1?lang=en
* 《微服务选型之Modern Node.js》 https://github.com/i5ting/modern-nodejs
* 帅龙攻城狮《镜像构建优化之路》 http://blog.tenxcloud.com/?p=1313
* 《微容器：更小的，更轻便的Docker容器》 http://blog.tenxcloud.com/?p=1302
* 黄鑫攻城狮的内部分享《Dockerfile技巧分享》
* 《Node 出现 uncaughtException 之后的优雅退出方案》 http://www.infoq.com/cn/articles/quit-scheme-of-node-uncaughtexception-emergence
* 《Express Error handling》 https://expressjs.com/en/guide/error-handling.html
* 《Promise 迷你书》 http://liubin.org/promises-book/
* 《如何把 Callback 接口包装成 Promise 接口》 http://www.75team.com/post/how-to-convert-callback-to-promise.html
