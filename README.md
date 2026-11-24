# Hands

Controla tu Mac con las manos usando solo la cámara: mueve el cursor, haz click, arrastra, haz scroll y cambia de escritorio. Es una app de barra de menú en Swift con Apple Vision.

**Privacidad:** el video se procesa en la Mac; no se guarda ni se envía. La app arranca apagada, con la cámara apagada.

> Proyecto experimental. Los gestos se probaron con manos sintéticas y pocas fotos; la precisión depende de la luz, el ángulo y la cámara.

## Contenido

- [Requisitos](#requisitos)
- [Instalación](#instalación)
- [Encender con Siri](#encender-con-siri)
- [Encender desde el iPhone](#encender-desde-el-iphone)
- [Gestos](#gestos)
- [Ajustes](#ajustes)
- [Diagnóstico](#diagnóstico)
- [Problemas frecuentes](#problemas-frecuentes)
- [Arquitectura](#arquitectura)
- [Limitaciones](#limitaciones)

## Requisitos

- macOS 15 o posterior, con cámara. Desarrollado en macOS 27 con Apple Silicon.
- Xcode y [XcodeGen](https://github.com/yonaskolb/XcodeGen): `brew install xcodegen`
- Un certificado "Apple Development" (Xcode → Settings → Accounts).

## Instalación

```bash
git clone https://github.com/AnthRG/hand-tracking.git
cd hand-tracking
cp Local.xcconfig.example Local.xcconfig
```

Pon tu Team ID en `Local.xcconfig` y corre:

```bash
make run
```

Compila, instala en `~/Applications/Hands.app` y abre la app. También copia `hands-remote` a `~/.local/bin`.

La primera vez que la enciendas, concede:

| Permiso | Para qué |
|---|---|
| Cámara | Ver tus manos |
| Accesibilidad | Mover el cursor, hacer click y enviar atajos |

| Comando | Qué hace |
|---|---|
| `make run` | Compila, instala y abre |
| `make test` | Corre los tests |
| `make shortcuts` | Prepara los atajos de Siri |
| `make stop` | Cierra la app |
| `make clean` | Borra los builds |

## Encender con Siri

En macOS, Siri [no corre por voz las frases que declara una app](https://developer.apple.com/forums/thread/764609), pero sí [corre un atajo por su nombre](https://support.apple.com/guide/shortcuts-mac/apdf22b0444c).

1. Activa "Hey Siri" en Ajustes del Sistema → Siri.
2. Con la app instalada, corre `make shortcuts` y pulsa **Agregar** en los dos atajos.
3. Di "Hey Siri, Hands on" o "Hey Siri, Hands down".

También funcionan `⌃⌥⌘H` y el menú de la app.

### JSON de los atajos

Están en [`shortcuts/hands-on.json`](shortcuts/hands-on.json) y [`shortcuts/hands-down.json`](shortcuts/hands-down.json). Atajos no importa JSON directamente: `make shortcuts` pone tu Team ID, los convierte a `.shortcut` y los firma en tu Mac. No publiques los `.shortcut` generados, porque la firma incluye tu identidad de Apple.

La parte que importa:

```json
{
  "WFWorkflowActionIdentifier": "com.sus.handtracking.HandsOnIntent",
  "WFWorkflowActionParameters": {
    "AppIntentDescriptor": {
      "TeamIdentifier": "TEAM_ID",
      "BundleIdentifier": "com.sus.handtracking",
      "Name": "Hands",
      "AppIntentIdentifier": "HandsOnIntent"
    }
  }
}
```

Para hacerlos a mano: Atajos → **+** → busca "Hands" → **Hands on** → nombra el atajo "Hands on". Repite con **Hands down**.

Si cambias `PRODUCT_BUNDLE_IDENTIFIER` en `project.yml`, cámbialo también en los JSON.

## Encender desde el iPhone

Útil si el iPhone responde a "Hey Siri" antes que la Mac. Probado con un servidor SSH local; falta probarlo con un iPhone real.

1. En la Mac, activa **Sesión remota** en Ajustes del Sistema → General → Compartir.
2. En el iPhone, crea un atajo con **Ejecutar script mediante SSH**:
   - Host: `nombre-de-tu-mac.local`
   - Puerto: `22`
   - Usuario: tu usuario de la Mac
   - Autenticación: clave SSH
   - Script: `on` (o `off` para apagar)
3. Copia la clave **pública** que muestra el atajo y autorízala en la Mac:

```bash
scripts/authorize-phone 'ecdsa-sha2-nistp256 AAAA... '
```

La clave queda limitada a `on`, `off` y `status`: no abre una terminal ni corre otros comandos.

Los atajos se sincronizan por iCloud. No uses en el iPhone los mismos nombres que en la Mac.

También desde la terminal:

```bash
hands-remote on
hands-remote status
hands-remote off
```

## Gestos

Para activar, muestra la mano **abierta y quieta 0.6 s**. Se desactiva al bajarla, al escribir o tras 10 s sin gestos.

### Encendidos por defecto

| Gesto | Acción |
|---|---|
| Índice y pulgar casi juntos | Mover el cursor al punto entre las dos puntas |
| Tocar índice y pulgar, y soltar | Click; dos rápidos, doble click |
| Tocar índice y pulgar, y sostener o mover | Arrastrar |
| Tocar medio y pulgar, con índice separado y meñique abierto | Click derecho |
| Índice y medio arriba, los demás cerrados, y mover | Scroll |
| Mano abierta, swipe izquierda / derecha | Escritorio derecho / izquierdo |
| Mano abierta, swipe arriba / abajo | Mission Control / ventanas de la app; el contrario cierra el que abriste con la mano |

### Apagados por defecto

| Gesto | Acción |
|---|---|
| Puño sostenido | Play / pausa |
| Puño con pulgar a la derecha / izquierda | Siguiente / anterior |
| Puño con pulgar arriba / abajo | Subir / bajar volumen (repite) |
| Pellizco con ambas manos, separar / juntar | Entrar / salir de pantalla completa |

## Ajustes

Desde el ícono de la barra de menú:

- **Cámara:** vista en vivo. El punto amarillo es la punta y el recuadro punteado equivale a la pantalla.
- **Gestos:** enciende, apaga o cambia la acción. Cursor, click y scroll solo se encienden o apagan.
- **Sensibilidad:** área de la cámara, suavizado, pellizco, swipe y tiempo de activación.
- **Panel de esquina:** muestra tu mano con una leyenda; puedes moverlo u ocultarlo.

## Diagnóstico

Con la app encendida: menú → **Grabar diagnóstico (30 s, solo puntos)**. Guarda las coordenadas de las articulaciones, sin video, en `~/Library/Application Support/Hands/trace.jsonl`.

```bash
swift run handprobe --trace ~/Library/Application\ Support/Hands/trace.jsonl
swift run handprobe foto.jpg
```

El primero resume fps, tiempo de detección y cortes del cursor. El segundo clasifica la pose de una foto.

## Problemas frecuentes

| Problema | Qué revisar |
|---|---|
| El cursor no se mueve | Permiso de Accesibilidad. Si ya estaba, quítalo y vuelve a darlo. |
| Siri dice que no puede | Que existan los atajos "Hands on" y "Hands down" en Atajos |
| Los atajos no encuentran la acción | Que la app esté en `~/Applications` y se haya abierto una vez |
| Los escritorios no cambian | Ajustes del Sistema → Teclado → Atajos → Mission Control |
| No llega a los bordes | Cambia "Área de la cámara" |
| Se corta al moverlo rápido | Más luz de frente; con poca luz la imagen sale borrosa |
| Aparecen efectos sobre el video | Apaga las Reacciones en el menú de video de macOS |

## Arquitectura

```
cámara → HandVision → HandTracker → GestureEngine → SystemController
```

| Carpeta | Contenido |
|---|---|
| `Sources/HandCore` | Rasgos, poses y motor de gestos, sin dependencias del sistema |
| `Sources/HandVision` | Detector con Apple Vision y segundo intento por región |
| `Sources/handprobe` | Herramienta de diagnóstico |
| `App` | Cámara, eventos del sistema, interfaz, Siri y control remoto |
| `shortcuts` | Plantillas JSON de los atajos |
| `scripts` | Control remoto, autorización del iPhone y generador de atajos |
| `Tests` | Tests con manos sintéticas |

Las coordenadas están en alturas de cuadro, vistas desde el usuario, con Y hacia arriba.

## Limitaciones

- Apple Vision entrega puntos 2D: al rotar la mano pueden confundirse "casi juntos", el toque y el scroll.
- Si los dedos apuntan a la cámara, la pose puede no reconocerse.
- Pantalla completa actúa sobre la ventana enfocada. Para un video web, asigna "Video a pantalla completa (F)".
- El cursor se mueve dentro de la pantalla donde está; no cruza entre monitores.
