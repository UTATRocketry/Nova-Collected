# Set up an operator laptop

The operator laptop needs **no software and no repos**. It only opens two web
pages on the ops PC, so setup is two desktop shortcuts and a network address.

## 1. Put the laptop on the station network

Give the laptop's ethernet adapter a static address on the `192.168.137.x`
subnet, for example `192.168.137.50`, mask `255.255.255.0`.

## 2. Copy the shortcuts

Copy `ops\operator\Nova Console.url` and `ops\operator\novaOps UI.url` from
this repo to the laptop's desktop. They're plain text files, so there's nothing
to install and no script to run. To point one elsewhere, open it in Notepad and
edit the URL line.

| Shortcut | Opens |
|---|---|
| Nova Console | `http://192.168.137.1:8080` |
| novaOps UI | `http://192.168.137.1:3000` |

> [!NOTE]
> `Setup-OperatorLaptop.ps1`, which would do both steps, isn't in the repo yet.

## 3. Verify

Open **Nova Console**. Every row should be green. If the page doesn't load,
follow [SUPPORT.md: The operator laptop can't reach the station](../../SUPPORT.md#the-operator-laptop-cant-reach-the-station).
