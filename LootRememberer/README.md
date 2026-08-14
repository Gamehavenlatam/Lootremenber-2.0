# Loot Rememberer

*[English below / Inglés más abajo]*

Addon para World of Warcraft (compatible con WoW Ascension, cliente 3.3.5) que recuerda tu elección de Need / Greed / Desencantar / Pasar para cada ítem, y la vuelve a aplicar automáticamente la próxima vez que ese ítem te salga en un roll de loot.

## ✨ Características

- **Clic derecho** sobre el botón de need/greed/desencantar/pasar para recordar tu elección para ese ítem.
- **Auto-aplicación**: la próxima vez que ese mismo ítem aparezca en un roll, el addon lo rollea automáticamente por ti.
- **Mensajes de chat**: te avisa en el chat cuándo guardó una elección y cuándo aplicó una automáticamente.
- **Ventana de historial** (`/lootrememberer` o `/lr`): revisa y borra tus registros guardados, con paginación y filtro de búsqueda.
- **Botón de minimapa**: clic izquierdo abre la lista de registros, clic derecho abre la configuración.
- **Panel de configuración** (`/lr config`, o desde `Interfaz > AddOns`):
  - **Lista por personaje o por cuenta**: elige si cada personaje tiene su propia lista de decisiones o si todos comparten una sola.
  - **Mostrar/ocultar** el botón de minimapa.
  - **Ventana de chat de destino**: elige a qué ventana de chat se mandan los mensajes del addon (útil si usas doble ventana de chat, como en ElvUI).
- Compatible con la UI estándar de Blizzard y con **ElvUI**.

## 📦 Instalación

1. Descarga el `.zip` de este repositorio (o clónalo).
2. Copia la carpeta `LootRememberer` completa (incluyendo la subcarpeta `Libs`) a:
   ```
   World of Warcraft\Interface\AddOns\
   ```
3. Reinicia el juego o usa `/reload`.

## 🎮 Uso

- **Clic derecho** en un botón de need/greed/DE/pasar cuando aparece una ventana de loot roll → se guarda tu elección para ese ítem.
- **`/lootrememberer`** o **`/lr`** → abre/cierra la ventana de historial.
- **`/lr config`** → abre el panel de configuración.

## 🛠️ Dependencias incluidas

El addon incluye (en la carpeta `Libs`) las siguientes librerías de terceros, necesarias para funcionar:
- LibStub
- CallbackHandler-1.0
- Ace3: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0, AceGUI-3.0, AceHook-3.0, AceLocale-3.0, AceDB-3.0, AceConfig-3.0
- LibDataBroker-1.1
- LibDBIcon-1.0

## 👤 Créditos

- Autor original: Bilal Akil
- Mantenimiento, correcciones (Ace3, compatibilidad con Ascension) y nuevas características (minimapa, configuración, perfiles por personaje/cuenta, selector de ventana de chat) añadidas posteriormente.

---

# Loot Rememberer (English)

World of Warcraft addon (compatible with WoW Ascension, 3.3.5 client) that remembers your Need / Greed / Disenchant / Pass choice for each item, and automatically re-applies it the next time that item comes up in a loot roll.

## ✨ Features

- **Right-click** the need/greed/disenchant/pass button to remember your choice for that item.
- **Auto-apply**: the next time that same item appears in a roll, the addon rolls it for you automatically.
- **Chat messages**: notifies you in chat when a choice is saved and when one is auto-applied.
- **History window** (`/lootrememberer` or `/lr`): browse and delete saved records, with pagination and search filter.
- **Minimap button**: left-click opens the records list, right-click opens the settings panel.
- **Settings panel** (`/lr config`, or from `Interface > AddOns`):
  - **Per-character or account-wide list**: choose whether each character has its own list of loot decisions, or whether all characters share a single list.
  - **Show/hide** the minimap button.
  - **Target chat window**: choose which chat window the addon's messages are sent to (useful if you run a dual chat window setup, like ElvUI's).
- Compatible with the standard Blizzard UI and with **ElvUI**.

## 📦 Installation

1. Download this repository's `.zip` (or clone it).
2. Copy the entire `LootRememberer` folder (including the `Libs` subfolder) to:
   ```
   World of Warcraft\Interface\AddOns\
   ```
3. Restart the game or use `/reload`.

## 🎮 Usage

- **Right-click** a need/greed/DE/pass button when a loot roll window appears → your choice for that item is saved.
- **`/lootrememberer`** or **`/lr`** → opens/closes the history window.
- **`/lr config`** → opens the settings panel.

## 🛠️ Bundled dependencies

The addon bundles (in the `Libs` folder) the following third-party libraries required to run:
- LibStub
- CallbackHandler-1.0
- Ace3: AceAddon-3.0, AceConsole-3.0, AceEvent-3.0, AceGUI-3.0, AceHook-3.0, AceLocale-3.0, AceDB-3.0, AceConfig-3.0
- LibDataBroker-1.1
- LibDBIcon-1.0

## 👤 Credits

- Original author: Bilal Akil
- Maintenance, fixes (Ace3, Ascension compatibility) and later features (minimap button, settings panel, per-character/account profiles, chat window selector) added afterwards.
