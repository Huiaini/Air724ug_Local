PROJECT = "air724ug-forwarder"
VERSION = "1.0.0"

require "log"
LOG_LEVEL = log.LOGLEVEL_INFO
require "config"
require "audio"
audio.setStrategy(1)
require "cc"
require "common"
require "http"
require "misc"
require "net"
require "netLed"
require "ntp"
require "powerKey"
require "record"
require "ril"
require "sim"
require "sms"
require "sys"
require "util_mobile"
require "util_audio"
require "util_http"
require "util_notify"
require "util_temperature"
require "util_ntp"
require "util_config_loader"
require "handler_call"
require "handler_powerkey"
require "handler_sms"
require "usbmsc"

-- 输出音频通道选项, 0:听筒 1:耳机 2:喇叭
-- 输入音频通道选项, 0:main_mic 1:auxiliary_mic 3:headphone_mic_left 4:headphone_mic_right

-- 静音音频通道
AUDIO_OUTPUT_CHANNEL_MUTE = 0
AUDIO_INPUT_CHANNEL_MUTE = 1
-- 正常音频通道
AUDIO_OUTPUT_CHANNEL_NORMAL = 2
AUDIO_INPUT_CHANNEL_NORMAL = 0

audio.setChannel(AUDIO_OUTPUT_CHANNEL_NORMAL, AUDIO_INPUT_CHANNEL_NORMAL)

-- 配置内部 PA 类型 audiocore.CLASS_AB, audiocore.CLASS_D
audiocore.setpa(audiocore.CLASS_D)
-- 配置外部 PA
-- pins.setup(pio.P0_14, 0)
-- audiocore.pa(pio.P0_14, 1, 0, 0)
-- audio.setChannel(1)

-- 设置睡眠等待时间
-- ril.request("AT+WAKETIM=0")

-- 定时查询温度
sys.timerLoopStart(util_temperature.get, 1000 * 60)
-- 定时查询 信号强度 基站信息
net.startQueryAll(1000 * 60, 1000 * 60 * 10)

sys.taskInit(function()
    -- 等待 U 盘挂载
    -- usbmsc.mscTask 会先 wait 1s，再预留 2s 给文件系统稳定后才发布事件，
    -- 2s 超时会导致启动阶段过早跳过 config.bin。
    local usbmsc_ready = sys.waitUntil("USBMSC_MOUNTED", 1000 * 8)
    if not usbmsc_ready then
        log.warn("main", "wait USBMSC_MOUNTED timeout")
    end

    -- 尝试读取 U 盘配置文件
    -- 优先级: 明文 > 密文
    -- local config_path_plain = "/usbmsc0/config.lua"
    local config_path_cipher = "/usbmsc0/config.bin"

    -- if io.exists(config_path_plain) then
    --     log.info("main", "load config from " .. config_path_plain)
    --     local chunk, err = loadfile(config_path_plain)
    --     if chunk then
    --         chunk("config")
    --     else
    --         log.error("main", "load config error", err)
    --     end
    if io.exists(config_path_cipher) then
        log.info("main", "load config from " .. config_path_cipher)
        local ok, mode_or_err = util_config_loader.load_from_file(config_path_cipher)
        if ok then
            log.info("main", "config apply success", mode_or_err)
        else
            log.error("main", "config apply failed", mode_or_err)
        end
    else
        log.info("main", "load config from default config.lua")
    end

    -- RNDIS
    ril.request("AT+RNDISCALL=" .. (config.RNDIS_ENABLE and 1 or 0) .. ",0")

    -- NET 指示灯, LTE 指示灯
    if config.LED_ENABLE then
        pmd.ldoset(2, pmd.LDO_VLCD)
    end
    netLed.setup(true, pio.P0_1, pio.P0_4)
    netLed.updateBlinkTime("SCK", 50, 50)
    netLed.updateBlinkTime("GPRS", 200, 2000)

    -- 开机查询本机号码
    sim.setQueryNumber(true)
    ril.request("AT+CNUM")
    sys.timerStart(ril.request, 3000, "AT+CNUM")
    -- 如果查询不到本机号码, 可以取消下面注释的代码, 尝试手动写入到 SIM 卡, 写入成功后注释掉即可
    -- sys.timerStart(ril.request, 5000, 'AT+CPBS="ON"')
    -- sys.timerStart(ril.request, 6000, 'AT+CPBW=1,"+8618888888888",145')

    -- SIM 自动切换开关
    ril.request("AT*SIMAUTO=1")

    -- 等待网络就绪
    sys.waitUntil("IP_READY_IND", 1000 * 60 * 2)

    -- 等待获取 Band 值
    -- sys.wait(1000 * 5)

    -- 开机通知
    if config.BOOT_NOTIFY then
        local function boot_poweron_reason_zh()
            local r = rtos.poweron_reason()
            local tab = {
                [0] = "电源键或上电开机",
                [1] = "充电或下载完成开机",
                [2] = "闹钟开机",
                [3] = "软件重启",
                [4] = "原因未知",
                [5] = "RESET键复位",
                [6] = "异常重启",
                [7] = "工具控制重启",
                [8] = "内部看门狗重启",
                [9] = "外部复位",
                [10] = "充电开机",
            }
            local name = tab[r]
            if name then return name end
            if rtos.POWERON_CHARGER and r == rtos.POWERON_CHARGER then return "充电开机" end
            return "开机原因(" .. tostring(r) .. ")"
        end
        local function boot_notify_suffix()
            local s = config.BOOT_NOTIFY_SUFFIX
            if type(s) ~= "string" then s = "reason_zh" end
            if s == "none" then return "" end
            if s == "reason" then return tostring(rtos.poweron_reason()) end
            if s == "reason_zh" then return boot_poweron_reason_zh() end
            return s
        end
        local suffix = boot_notify_suffix()
        -- 统一由 util_notify 中的 NOTIFY_HEADER 控制通知头, 开机只提供正文
        if suffix == "" then suffix = "开机" end
        util_notify.add(suffix, nil, { keep_full_append_info = true })
    end

    -- 定时查询流量
    if config.QUERY_TRAFFIC_INTERVAL and config.QUERY_TRAFFIC_INTERVAL >= 1000 * 60 then
        sys.timerLoopStart(util_mobile.queryTraffic, config.QUERY_TRAFFIC_INTERVAL)
    end

    -- 开机同步时间
    util_ntp.sync()
    sys.timerLoopStart(util_ntp.sync, 1000 * 30)
end)

-- 验证 PIN 码
sys.subscribe("SIM_IND", function(msg)
    if msg == "SIM_PIN" then
        util_mobile.pinVerify()
    end
end)

-- 系统初始化
sys.init(0, 0)
sys.run()
