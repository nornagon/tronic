coffee = require 'coffee-script'
vm = require 'vm'
connect = require 'connect'
browserChannel = require('browserchannel').server

comm = new (require('events').EventEmitter)

# TODO: sandbox
master = ((comm) ->
  code = '''
order ?= []
client_code = 'alert("hi")'
(msg) ->
  ctrl.broadcast(msg)
  switch msg.type
    when 'data'
      switch msg.data.cmd
        when 'patch'
          updateCode(msg.data.code)
          ctrl.broadcast {cmd:'info',message:\"fun updated by #{msg.sender}\"}
        when 'order?'
          ctrl.sendMessage msg.sender, {cmd:'order',order:order}
        when 'update'
          ctrl.sendMessage msg.sender, {cmd:'eval',code:client_code}
    when 'join'
      order.push msg.sender
    when 'leave'
      i = order.indexOf msg.sender
      order.splice i, 1
'''
  state = {}
  ctrl = {
    broadcast: (msg) ->
      comm.emit 'broadcast', msg
  }
  updateCode = (source) ->
    code = source
  sandbox = vm.Script.createContext {updateCode, ctrl}
  fun = (msg) ->
    coffee.eval(code, {sandbox})(msg)
  comm.on 'message', (sender, data) ->
    fun {sender, type: 'data', data}
  comm.on 'join', (sender) ->
    fun {sender, type: 'join'}
  comm.on 'leave', (sender) ->
    fun {sender, type: 'leave'}
)(comm)

comm.on 'broadcast', (msg) ->
  broadcast msg

comm.on 'sendMessage', (to, msg) ->
	sessions[to]?.send msg

sessions = {}

broadcast = (message, except) ->
  for id, s of sessions
    s.send message unless id == except

onConnect = (session) ->
  sessions[session.id] = session
  console.log "New session: #{session.id} from #{session.address} with cookies #{session.headers.cookie}"
  comm.emit 'join', session.id
  session.on 'message', (data) ->
    console.log "#{session.id} sent #{JSON.stringify data}"
    comm.emit 'message', session.id, data

  session.on 'close', (reason) ->
    comm.emit 'leave', session.id
    console.log "#{session.id} disconnected (#{reason})"
    delete sessions[session.id]

server = connect(
  connect.static "#{__dirname}/static"
  browserChannel onConnect
).listen 4321
