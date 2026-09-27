# ============================================================================
#  nova.config.ps1 - single source of truth for the Nova ground station.
#
#  EVERY script and service definition reads its paths, ports and addresses
#  from this file. If something moves, change it here and re-run:
#      .\ops\Nova.ps1 install -Env prod
#
#  This file is dot-sourced, not executed. It must only define $NovaConfig.
# ============================================================================

$NovaConfig = @{

    # -- Network ------------------------------------------------------------
    # Hosts on the ground station LAN. See ops/README.md for the rationale
    # behind static addressing and the .local hostname fallbacks.
    Hosts = @{
        Server     = '192.168.137.1'      # this Windows PC ("Nova-Server")
        NovaGround = '192.168.137.10'     # Raspberry Pi running novaGround
        NovaThermo = '192.168.137.20'     # Raspberry Pi running novaThermo
    }

    # mDNS names, used only by the console's reachability check as a fallback
    # when the static address does not answer. Requires avahi-daemon on the Pi.
    HostNames = @{
        NovaGround = 'novaground.local'
        NovaThermo = 'novathermo.local'
    }

    # -- MQTT broker (runs on this PC) --------------------------------------
    Broker = @{
        Host        = '127.0.0.1'   # services on this PC talk to it over loopback
        Port        = 1883
        ServiceName = 'mosquitto'   # Windows service name from the Mosquitto installer
    }

    # -- Environments -------------------------------------------------------
    # Two fully independent stacks. 'prod' is what flies; 'dev' is for bench
    # work and never auto-starts, so a half-finished branch can never come up
    # on boot and fight prod for the broker or the serial port.
    Environments = @{

        prod = @{
            BackendPath   = 'C:\Nova\prod\novaOps-back'
            FrontendPath  = 'C:\Nova\prod\novaOPS-front'
            BackendPort   = 8000
            FrontendPort  = 3000
            ConsolePort   = 8080
            # Automatic (delayed) start - comes up on boot with no operator input.
            StartMode     = 'Automatic'
            # Serial port for the FAS RS-422 bridge. Empty string is valid: the
            # bridge starts idle and novaOps can set the port at runtime.
            FasPort       = 'COM3'
            FasBaud       = 460800
            # Set a real password before the stack leaves the bench.
            AdminPassword = 'admin123'
            GitBranch     = 'main'
        }

        dev = @{
            BackendPath   = 'C:\Nova\dev\novaOps-back'
            FrontendPath  = 'C:\Nova\dev\novaOPS-front'
            BackendPort   = 8001
            FrontendPort  = 3001
            ConsolePort   = 8081
            # Manual - dev services never start on boot. Start them by hand:
            #     .\ops\Nova.ps1 start -Env dev
            StartMode     = 'Manual'
            FasPort       = ''          # idle by default so it cannot grab prod's port
            FasBaud       = 460800
            AdminPassword = 'dev'
            GitBranch     = 'fas_integration'
        }
    }

    # -- Shared machine layout ----------------------------------------------
    # Deliberately outside both repo trees so an update or a fresh clone never
    # destroys logs or the console's generated config.
    Root       = 'C:\Nova'
    LogDir     = 'C:\Nova\logs'
    BinDir     = 'C:\Nova\bin'
    ConsoleCfg = 'C:\Nova\console.json'

    # Python used to run the console service. Leave empty to auto-detect
    # (system Python first, backend venv as a fallback). The console is
    # stdlib-only and deliberately does NOT use the backend's venv, so it keeps
    # running while an update tears that venv down and rebuilds it.
    ConsolePython = ''

    # WinSW is fetched once and cached in BinDir. Field machines are often
    # offline, so Nova.ps1 fails with a clear message rather than hanging.
    WinSW = @{
        Exe = 'C:\Nova\bin\WinSW.exe'
        Url = 'https://github.com/winsw/winsw/releases/download/v2.12.0/WinSW-x64.exe'
    }
}
