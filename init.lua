------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

-- This code is used on a lolin NodeMCU microcontroller.
-- The (micro)controller connects itself to the wifi. It then checks the sntp server for the current time and checks if it is monday to friday between 8am and 4pm.
-- After that it collects the job build status from the Jenkins API via JSON.
-- With the build status it decides if the build was successful or not and if the buildstatus is different from the last time it will call functions to make specific sounds with a beeper.

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

resetPins = function()
  gpio.mode(1, gpio.OUTPUT)                                                                                                   -- 5 gpio pin
  gpio.mode(2, gpio.OUTPUT)                                                                                                   -- 4 gpio pin
  gpio.mode(5, gpio.OUTPUT)                                                                                                   -- 14 gpio pin
  gpio.write(1, gpio.HIGH)                                                                                                    -- set lamp to off
  gpio.write(2, gpio.HIGH)                                                                                                    -- set lamp to off
  gpio.write(5, gpio.LOW)                                                                                                     -- set beeper to off
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function setUpWiFi()
  dofile('config.lua')
  print("Setting up WiFi")
  wifi.setmode(wifi.STATION)                                                                                                    -- Set mode for wifi
  print("Wifi mode was set to Station")
  wifi.sta.config(AP_SSID, AP_PASSWORD);                                                                                              -- Sets ssid and password to enter wifi
  wifi.sta.connect()                                                                                                            -- Connects with the wifi
  local cnt = 0                                                                                                                 -- Counter for wifi timeout
  tmr.alarm(3, 1000, 1, function()                                                                                              -- timer
    if (wifi.sta.getip() == nil) and (cnt < 20) then                                                                            -- checks if wifi connection could be established
      print("Creating Connection")
      cnt = cnt + 1                                                                                                             -- timeout counter
    else
      tmr.stop(3)                                                                                                               -- stops timer
      if (cnt < 20) then                                                                                                        -- checks if connection established or timeout
        print("Connecting successful!")
        print("IP: "..wifi.sta.getip())                                                                                         -- Prints the IP
        checkTime()                                                                                                             -- See checkTime() below for more information
      else
        print("Wifi setup time more than 20s, Please verify wifi.sta.config() function. Then re-download the file.")            -- Error message for timeout
      end
    cnt = nil;
    collectgarbage();                                                                                                           -- Garbage collector
    end
  end)
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function daylightSaving()
      if (tm["mon"] < 03 or tm["mon"] > 10) then
        return false
      end
      if (tm["mon"] > 03 and tm["mon"] < 10) then
        return true
      end
      
      local wdayNew = tm["wday"]
      if (tm["wday"] == 01) then
        wdayNew = 07
      else
        wdayNew = tm["wday"] -1
      end
      
      local previousSunday = tm["day"] - wdayNew;
      if (tm["mon"] == 03) then
        return previousSunday >= 25
      end
      if (tm["mon"] == 10) then
        return previousSunday < 25
      end
    end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function checkTime(sck)
  local permanentStatus = table.buildSuccess                                                                                                                  -- Permanent status variable to check the last status of build success
  local changedStatus = false                                                                                                                                 -- Set to true if last build success was different than the one before
  tmr.alarm(0,1000,tmr.ALARM_AUTO,function()                                                                                                                  -- Repeating timer
    tm = rtctime.epoch2cal(rtctime.get())                                                                                                                     -- Gets a time table with todays date calculated from 01.01.1970

    if (daylightSaving() == true) then
      tm["hour"] = tm["hour"] + 2
    elseif (daylightSaving() == false) then
      tm["hour"] = tm["hour"] + 1
    else
      print("daylightsaving returns nil, unexpected error")
    end
    print(string.format("%04d/%02d/%02d %02d:%02d:%02d %02d", tm["year"], tm["mon"], tm["day"], tm["hour"], tm["min"], tm["sec"], tm["wday"]))                -- Prints todays date and time plus weekday
    if (tm["wday"] == 01) then                                                                                                                                -- Checks if it is sunday
      print("It is weekend, no need to check the job statuses")
      resetPins()
    elseif (tm["wday"] == 07) then                                                                                                                            -- Checks if it is friday
      print("It is weekend, no need to check the job statuses")
      resetPins()
    else                                                                                                                                                      -- Should only activate if it is monday to friday
      if (tm["hour"] > 07) then                                                                                                                               -- Checks if it is 8am or later
        if (tm["hour"] < 17) then                                                                                                                             -- Checks if it is 5pm or earlier
          updateLamp()                                                                                                                                        -- See updateLamp() below for more information
        else
          resetPins()
        end
      else
        resetPins()
      end
    end
  end)
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function generateHeader()
  authentication = encoder.toBase64(JENKINS_USERNAME .. ':' ..JENKINS_PASSWORD)
  generatedHeader = "Authorization: Basic " .. authentication .. "==\r\n"
  return generatedHeader
end
  
------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function updateLamp()
  Header = generateHeader()
  http.get(API_URL, Header, function(code, data)                                                                              -- Sends a http GET request to the jenkins API
    if (code < 0) then                                                                                                        -- If no code is returned it failed
      print("HTTP request failed")
      print(code)                                                                                                             -- Prints the Error code for debugging
  else
    if (code == 200) then                                                                                                     -- If the code is 200 (standard http response code)
      table = cjson.decode(data)                                                                                              -- Decodes the json from the jenkins API
      if (permanentStatus == table.buildSuccess) then                                                                         -- if the buildstatus is the same as last time
        if (table.buildSuccess) then                                                                                          -- Checks if build was successful
          shine("green")                                                                                                      -- See shine() for more information
      else                                                                                                                    -- Build was not successful
        shine("red")                                                                                                          -- See shine() for more information
      end
      else                                                                                                                    -- Build status is not the same as last time
        permanentStatus = table.buildSuccess                                                                                  -- Set the permanent build status to the new build status
        if (table.buildSuccess) then                                                                                          -- Checks if build was successful
          shine("green")                                                                                                      -- See shine() for more information
          beep(3)                                                                                                             -- See beep() for more information
        else                                                                                                                  -- Build was not successful
          shine("red")                                                                                                        -- See shine() for more information
          beep(2)                                                                                                             -- See beep() for more information
        end
      end
    else                                                                                                                      -- If http response code was not 200
      print(code)                                                                                                             -- Prints the code to see what http problem occurred
    end
  end
  end)
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function shine(color)
  print(color)
  if (color=="green") then
    gpio.write(1, gpio.LOW)
    gpio.write(2, gpio.HIGH)
  elseif (color=="red") then
    gpio.write(1, gpio.HIGH)
    gpio.write(2, gpio.LOW)
  end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

function beep(counter)
  if (counter > 0) then
    tmr.alarm(2,300,tmr.ALARM_SEMI,function()
      gpio.write(5, gpio.HIGH)
      tmr.alarm(2,300,tmr.ALARM_SEMI,function()
        gpio.write(5, gpio.LOW)
        counter = counter - 1
        beep(counter)
      end)
    end) 
  end
end

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

cjson = require "cjson"                                                                                                     -- Imports cjson
sntp.sync()                                                                                                                 -- Synchronizes with sntp server
resetPins()                                                                                                                 -- Sets modes and turns off used pins
setUpWiFi()                                                                                                                 -- Sets up wifi AND CALLS checkTime()

------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------