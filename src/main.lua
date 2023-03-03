require 'lib.require'
cargo = require 'lib.cargo'
assets = cargo.init('assets')
require 'lib.inspect-print' ( require 'lib.inspect' )

local Signal = require 'lib.hump.signal'
local spritesheets = require('bedsheets').load('assets/img')
local machine = require 'lib.statemachine'

local love = love
local debug = true
local joystick
local lg=love.graphics
local music = {}
local img = {}
local sfx = {}

local w=84 -- pixels
local h=48 -- pixels
local scale = 4

local blocks = 12
local blockW = w/blocks

local palette = {
  {0xc7/0xff,0xf0/0xff,0xd8/0xff},--1-light
  {0x43/0xff,0x52/0xff,0x3d/0xff},--2-dark
}
local light, dark = palette[1], palette[2]

local scaleWindow = function()
  if scale < 1 then scale = 1; return end
  if love.system.getOS() == "Android" then
    local dw, dy = love.graphics.getDimensions()
    -- setting mode height to graphics width --> if width > screen width it will go to landscape (when scale is too big)
    love.window.setMode(scale*w, dw, {fullscreen = false} )
  else
    if not love.window.setMode( scale*w, scale*h ) then scale = 8 end
  end
end


---

local state = {
  connecting ={},
  countdown = {},
  play = {},
  over ={},
}

state.current = state.connecting


local deaths=0

local hand = {}
function hand:new()
  self.x=-580
  self.y=-11
  self.speed=1
end

function hand:update(dt)
  self.x = self.x + dt*self.speed*0.85
end
function hand:draw()
  lg.draw(assets.img.hand, self.x, self.y)
end
function hand:reaches(x)
  return x<self.x+557
end




---
local map={}

function map:new()
  self.blocks= {27, 29, 20, 20, 30, 27, 27, 20, 27, 27, 27, 27, 27, 27 }
  self.relative=0 -- relative offset from 0 to blockW
  self.speed=20
end

function map:newBlock()
  local last = self.blocks[#self.blocks]
  local last2 = self.blocks[#self.blocks-1]
  local rand100 = love.math.random(100)
  if rand100>85 and not (last==99 and last2==99) then
    return 99
  end
  if rand100>70 and last~=99 then
    return last
  end

  local new = math.min(40, math.max(18, love.math.random(last-5, last+5)))
  return new
end

function map:update(dt)
  self.relative = self.relative+dt*self.speed
  self.speed=math.min(100, self.speed*1.0003)

  if self.relative >= blockW then
    self.relative = self.relative - blockW
    table.remove(self.blocks, 1)
    table.insert(self.blocks, self:newBlock())
  end
end


function map:ground(x)
  if x>w then return 0 end
  return self.blocks[math.floor((x+self.relative)/blockW)+1]
end

function map:draw()
  lg.setColor(dark)
  for i, g in ipairs(self.blocks) do
    lg.rectangle("fill", (i-1)*blockW-self.relative, g, blockW, h)
  end
end

local jumpKeys = {'up', 'space', 'rshift', 'lshift', 'rctrl', 'lctrl'}
for _,v in pairs(jumpKeys) do
  jumpKeys[v]=v
end



---
local runner ={}
function runner:new()
  self.animations={
    t=0,
    jumping={tag="jumping",dur=0.8},
    flying={tag="jumping", dur=0.8},
    running={tag="running",dur=0.3},
  }
  self.x=62
  self.y=27
  self.w=8
  self.h=8
  self.jumpVelocity=0 -- positive = jumping up, negative, falling down
  self.fsm = machine.create({
    initial = 'running',
    events = {
      {name = 'jump', from = 'running', to = 'jumping'}, -- jumping up while still holding the jump button
      {name = 'jumpStop', from = 'jumping', to = 'flying'}, -- still jumping up after releasing the jump button or falling down
      {name = 'fall', from = 'running', to = 'flying'}, -- when running over a hole
      {name = 'land', from = {'flying', 'jumping'}, to = 'running'},
    }
  })
  self.fsm.onstatechange = function(_selffsm, _event, _from, to)
  --print(to)
  end

  self.fsm.onland = function(_selffsm, _event, _from, _to)
    self.jumpVelocity = 0
    --runner.y = map:ground(runner.x)
  end
end




function runner:update(dt)

  if love.keyboard.isDown('left') then
    local newx = self.x-dt*18
    if self.y <= map:ground(newx-1) then
      self.x = newx
    end
  end
  if love.keyboard.isDown('right') then
    local newx = self.x+dt*4
    if self.y <= map:ground(newx+1) then
      self.x = newx
    end
  end



  --if self.fsm:is('running') then
  local distanceToGround = map:ground(self.x) - self.y
  --print(self.y, self.x, map:ground(self.x), distanceToGround)
  if distanceToGround > 0 then
    self.fsm:fall()
  elseif distanceToGround >= -2 then -- auto climb small stairs
    self.y = self.y + distanceToGround
    self.fsm:land()
  else
    --print("push")
    self.x=self.x-1
  end

  --end

  if self.fsm:is('running') and (love.keyboard.isDown(jumpKeys) or #love.touch.getTouches() > 0) then
    self.fsm:jump()
  end

  if self.fsm:is('jumping') then
    self.jumpVelocity = self.jumpVelocity + dt*7
    if self.jumpVelocity > 0.95 then
      self.fsm:jumpStop()
    end
  end
  if self.fsm:is('jumping') or self.fsm:is('flying') then
    self.jumpVelocity = self.jumpVelocity - dt*3
  end
  if self.fsm:is('flying') and self.y >= map:ground(self.x) then
    self.y = map:ground(self.x)
    self.fsm:land()
  end




  self.y = self.y - self.jumpVelocity


  if self.y >= h+10 or self.x < 0 or hand:reaches(self.x) then gameOver() end





  self.animations.t=(self.animations.t+dt) % self.animations[self.fsm.current].dur
end

function runner:keyreleased(key)
  if jumpKeys[key] then self.fsm:jumpStop() end
end
function runner:touchreleased()
  self.fsm:jumpStop()
end


function runner:draw(x,y) -- TODO move this to bedsheets
  local spritesheet = spritesheets["runner"]
  local a = self.animations[self.fsm.current]
  local quads = spritesheet:getQuads(a.tag)
  local spriteNum = math.floor(self.animations.t / a.dur * #quads) + 1
  love.graphics.draw(spritesheet.image, quads[spriteNum], self.x-self.w/2, self.y-self.h)
end






function love.load()
  scaleWindow()

  lg.setDefaultFilter("nearest", "nearest")
  canvas = lg.newCanvas(w,h)
  canvas:setFilter("nearest", "nearest")


  assets.music.badinerie:setLooping(true)
  assets.music.badinerie:setVolume(0.85)

  lg.setNewFont("assets/font/nokiafc22cz.ttf",8 )


  Signal.emit('game_started')
end


function love.draw()
  lg.setCanvas(canvas)
  lg.setColor(light)
  lg.rectangle("fill", 0,0,w,h)
  state.current:draw()
  lg.setCanvas()
  lg.setColor(1,1,1)

  -- on android dw != w --> center
  local dw, dy = love.graphics.getDimensions()  
  lg.draw(canvas, (dw-w*scale)/2,0,0,scale, scale)
end

function love.update(dt)
  if state.current.update then state.current:update(dt) end
end


function init()
  map:new()
  runner:new()
  hand:new()
  state.countdown.n=3
end

function newGame()
  init()
  assets.music.badinerie:stop()
  assets.music.badinerie:play()
  state.current = state.play
end


function gameOver()
  deaths = deaths +1
  state.over.time = 0
  state.current = state.over
end



init()


--------------
function state.connecting:draw()
  lg.setColor(dark)
  lg.printf("Connecting People", 0, 27, w, "center")
end


function state.connecting:keypressed(key)
  state.current=state.countdown
end
function state.connecting:touchpressed()
  state.current=state.countdown
end





--------------
function state.countdown:update(dt)
  self.n=self.n - dt*3;
  if self.n < -0.5 then
    newGame()
  end
end

function state.countdown:draw()
  if self.n > 0 then
    lg.setColor(dark)
    lg.circle("fill", w/2, h/2, 8)
    lg.setColor(light)
    lg.printf(math.ceil(self.n), 1, 19, w, "center")
  else
    lg.setColor(dark)
    lg.printf("run!", 1, 19, w, "center")
  end
end




--------------
function state.play:update(dt)
  map:update(dt)
  runner:update(dt)
  hand:update(dt)
end



function state.play:draw()
  runner:draw()
  hand:draw()
  map:draw()
end

function state.play:keyreleased(key)
  runner:keyreleased(key)
end
function state.play:touchreleased()
  runner:touchreleased()
end








--------------
function state.over:update(dt)
  self.time = self.time+dt
  hand.speed=math.min(1300, math.max(10, hand.speed*1.1))
  hand:update(dt)

  if deaths >= 3 and self.time > 1.4 then
    state.current=state.countdown
  end
end


function state.over:draw()
  hand:draw()

  lg.setColor(dark)
  lg.rectangle("fill", 0,27, w, h)
  lg.setColor(light)
  lg.printf(getGameOverText(), 0, 27, w, "center")
end

function state.over:keypressed(key)
  state.current=state.countdown
end
function state.over:touchpressed()
  state.current=state.countdown
end


function getGameOverText()
  if deaths >3 and deaths < 7 then
    local t={
      "kurva",
      "piče vole",
      "fuck",
      "do prdele",
      "",
    }
    return t[ love.math.random( #t ) ]
  end

  local m ={
    "Game Over",
    "Game Over",
    "Game Over",
    "Game Over",
    "Game Over",
    "Game Over",
    "Why am I running?" ,
    "What is my score?" ,
    "I want to connect with people" ,
    "Are we there yet?" ,
    "The hand is going to get me" ,
    "..." ,
    "Who's hand is it" ,
    "I have to run faster" ,
    "I will escape next time" ,
    "I must try to be better" ,
    "This isn't good" ,
    "I'm not enjoying this" ,
    "What's the point?" ,
    "..." ,
    "You won!" ,
    "Just kidding, you didn't" ,
    "Why are you still playing?" ,
    "Game Over" ,
    "Game Over" ,
    "Game Over" ,
    "Do you think there's more?" ,
  }
  if m[deaths] then return m[deaths] else return m[1] end
end









-----controls

function love.keypressed(key)
  if key=='d' then debug = not debug end
  if key=='escape' then love.event.quit() end
  if key=='+' or key=='kp+' then scale = scale + 1; scaleWindow() end
  if key=='-' or key=='kp-' then scale = scale - 1; scaleWindow() end

  if state.current.keypressed then state.current:keypressed(key) end
end
function love.touchpressed( id, x, y, dx, dy, pressure )
  if state.current.touchpressed then state.current:touchpressed(id, x, y, dx, dy, pressure) end
end

function love.textinput(text)
  if text=='+' then scale = scale + 1; scaleWindow() end
  if text=='-' then scale = scale - 1; scaleWindow() end
end

function love.keyreleased(key)
  if state.current.keyreleased then state.current:keyreleased(key) end
end
function love.touchreleased( id, x, y, dx, dy, pressure )
  if state.current.touchreleased then state.current:touchreleased(id, x, y, dx, dy, pressure) end
end

