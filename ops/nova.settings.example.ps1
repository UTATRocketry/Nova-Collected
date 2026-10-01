# ============================================================================
#  nova.settings.example.ps1 - the reference settings for the Nova ground station.
#
#  Nova.ps1 reads ONLY ops\nova.settings.ps1, this machine's own copy. That copy
#  is never committed (.gitignore), so it can hold the real admin password and
#  this PC's COM port. If it does not exist yet, Nova.ps1 creates it from this
#  file - the same idea as .env.example and .env.
#
#  This file is the tracked base reference: change it through a PR when a
#  setting changes for every station, or a new one is added. A machine whose
#  nova.settings.ps1 lacks a setting added here later gets this file's value,
#  with a warning to copy it across.
#
#  After changing nova.settings.ps1, re-run:  .\ops\Nova.ps1 install -Env prod
#
#  Both files are dot-sourced, not executed. They must only define $NovaSettings.
# ============================================================================

$NovaSettings = @{

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
    #
    # There is no branch setting: prod runs exactly the commits pinned by a
    # release (Nova.ps1 deploy), and dev stays on whatever branch you check out
    # (Nova.ps1 get-changes -Ref <branch> switches it).
    Environments = @{

        prod = @{
            BackendPath   = 'C:\Nova\prod\backend'
            FrontendPath  = 'C:\Nova\prod\frontend'
            BackendPort   = 8000
            FrontendPort  = 3000
            ConsolePort   = 8080
            # Automatic (delayed) start - comes up on boot with no operator input.
            StartMode     = 'Automatic'
            # Serial port for the FAS RS-422 bridge. Empty string is valid: the
            # bridge starts idle and novaOps can set the port at runtime.
            FasPort       = 'COM3'
            FasBaud       = 115200   # RS-422 EGSE link; FMC-Interface-Contract.md section 2.1
            # Placeholder only. Set the real password in this machine's
            # ops\nova.settings.ps1, which is never committed.
            AdminPassword = 'admin123'
        }

        dev = @{
            BackendPath   = 'C:\Nova\dev\backend'
            FrontendPath  = 'C:\Nova\dev\frontend'
            BackendPort   = 8001
            FrontendPort  = 3001
            ConsolePort   = 8081
            # Manual - dev services never start on boot. Start them by hand:
            #     .\ops\Nova.ps1 start -Env dev
            StartMode     = 'Manual'
            FasPort       = ''          # idle by default so it cannot grab prod's port
            FasBaud       = 115200   # RS-422 EGSE link; FMC-Interface-Contract.md section 2.1
            AdminPassword = 'dev'
        }
    }

    # -- Branches (CONTRIBUTING.md) -----------------------------------------
    # Each code repo: `dev` collects merged work for hardware testing, `main`
    # is what prod runs. Releases are normally pinned from dev (or a hotfix or
    # release branch); anything else is allowed and just called out. The Nova
    # repo itself uses GitHub Flow on `main`.
    Branches = @{
        Dev           = 'dev'
        Prod          = 'main'
        HotfixPrefix  = 'hotfix/'
        ReleasePrefix = 'release/'
    }

    # -- Raspberry Pi (novaGround) -------------------------------------------
    # pin reads the tested commit from DevDir over SSH; deploy runs
    # nova-pi.sh there. Key-based SSH avoids a password prompt each time.
    Pi = @{
        User    = 'admin'
        ProdDir = '/home/admin/prod/novaGround'
        DevDir  = '/home/admin/dev/novaGround'
    }

    # -- Server state ------------------------------------------------------
    # Live config, recordings and history belong to the Server, not to any
    # code version, so they live outside every checkout: deploying a different
    # release never touches them.
    #   ConfigRoot\<env>\    live config the web interface edits
    #   ConfigRoot\history\  every config ever used, by content hash (automatic)
    #   DataRoot\<env>\      raw recordings + <recording>.meta.json
    #   ArchiveDir\          one self-contained bundle per finished recording
    ConfigRoot   = 'C:\Nova\config'
    DataRoot     = 'C:\Nova\data'
    ArchiveDir   = 'C:\Nova\archive'
    StateDir     = 'C:\Nova\state'
    ReleaseIndex = 'C:\Nova\releases.json'

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
