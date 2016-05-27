###
 * express-lane
 * https://github.com/devmode/express-lane
 *
 * Copyright (c) 2015 Sean M. Duncan
 * Licensed under the MIT license.
###

{ compact, flatten, filter, reject, isArray, isFunction } = require 'lodash'
qs = require 'qs'

class Builder

  constructor: (@router, @configurator) ->
    @middleware = []

  add: (verbs..., middleware) ->
    verbs = [ 'all' ] unless verbs.length
    binding = {}
    binding[verb] = middleware for verb in verbs
    @middleware.push binding

  build: ->
    @configurator.apply @
    (name, path, middleware..., handler) =>
      @router.route name, path, @middleware.concat(middleware)..., handler

class Router

  constructor: (@app) ->
    @routes = {}

  route: (name, path, bindings..., handler) =>
    @routes[name] = path
    verbs =
      get: [ 'get', 'GET' ]
      post: [ 'post', 'POST' ]
      put: [ 'put', 'PUT' ]
      patch: [ 'patch' ]
      delete: [ 'delete', 'DELETE', 'del' ]
      all: [ 'all' ]
      options: [ 'options', 'OPTIONS' ]
    resolve = (verb) ->
      for alias in verbs[verb]
        return handler[alias] if handler[alias]?
      undefined
    supported = ( verb for verb of verbs when resolve(verb)? )
    for it, index in bindings
      bindings[index] = all: it if isFunction it or isArray it
    for verb in supported
      middleware = compact flatten (binding[verb] ? binding.all for binding in bindings), true
      stack = compact flatten [ middleware, handler.middleware, resolve(verb) ], true
      @app[verb] path, flatten [
        filter stack, (it) -> it.length < 4 # req middleware
        filter stack, (it) -> it.length > 3 # err middleware
      ], true
    supported.push 'head' if 'get' in supported
    unless 'all' in supported
      @app.all path, (req, res, next) ->
        res.set 'allow', (verb.toUpperCase() for verb in supported).join ', '
        res.sendStatus 405

  custom: (type, custom...) =>
    if custom.length is 1 and isFunction(custom[0]) and custom[0].length is 0
      @[type] = new Builder(@, custom[0]).build()
    else
      @[type] = (name, path, middleware..., handler) =>
        @route name, path, custom.concat(middleware)..., handler

  uri_for: (name, params={}, req=undefined, full=false) =>
    url = @routes[name]
    throw Error("Route: #{name} not found.") unless url
    route_params = url.match(/:\w+\??/g) ? []
    for route_param in route_params
      name = route_param[1..]
      name = name[0...-1] if name.match /\?$/
      value = params[name] ? ''
      delete params[name]
      url = url.replace route_param, value
    query = qs.stringify params, encode: false
    url = url.replace /\/$/, '' if url.length > 1
    url += "?#{query}" if query.length
    url = "#{req.protocol}://#{req.get 'HOST'}#{url}" if full
    url

  middleware: () =>
    uri_for = @uri_for
    (req, res, next) ->
      router =
        path_for: (name, params) =>
          uri_for name, params
        uri_for: (name, params) =>
          uri_for name, params, req, true
        redirect_to: (name, params, full=false) =>
          res.redirect uri_for name, params, req, full
      res[name] = value for name, value of router
      res.locals.path_for = router.path_for
      res.locals.uri_for = router.uri_for
      next()

module.exports = (app) ->
  new Router app
