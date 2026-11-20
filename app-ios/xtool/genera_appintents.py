#!/usr/bin/env python3
"""
Genera Metadata.appintents/version.json e Metadata.appintents/extract.actionsdata
per l'app iPhone (RecompNuova) e per l'estensione Live Activity (RecompLive).

Su Linux/WSL xtool compila con SwiftPM senza l'estrattore proprietario di Xcode
(appintentsmetadataprocessor): senza questa cartella iOS ignora i Button(intent:)
nella Dynamic Island e nella schermata di blocco.
"""
import json
import pathlib
import sys


INTENTI = [
    ("Meno15RecuperoIntent", "Meno 15 secondi"),
    ("Piu15RecuperoIntent", "Più 15 secondi"),
    ("SaltaRecuperoIntent", "Salta recupero"),
    ("SegnaSerieIsolaIntent", "Segna serie fatta"),
]

PROTO_SESSIONE = "com.apple.link.systemProtocol.SessionStarting"


def mangled(modulo: str, nome: str) -> str:
    return f"{len(modulo)}{modulo}{len(nome)}{nome}V"


def costruisci_azione(modulo: str, nome: str, titolo: str) -> dict:
    m = mangled(modulo, nome)
    return {
        "actionConfiguration": {
            "actionSummary": {
                "wrapper": {
                    "otherParameterIdentifiers": []
                }
            }
        },
        "assistantDefinedSchemaTraits": [],
        "assistantDefinedSchemas": [],
        "authenticationPolicy": 0,
        "availabilityAnnotations": {
            "LNPlatformNameIOS": {"introducedVersion": "17.0"},
            "LNPlatformNameWildcard": {"introducedVersion": "*"},
        },
        "customIntentClassName": nome,
        "descriptionMetadata": {
            "descriptionText": {
                "alternatives": [],
                "key": titolo,
            },
            "searchKeywords": [],
        },
        "effectiveBundleIdentifiers": [],
        "fullyQualifiedTypeName": f"{modulo}.{nome}",
        "identifier": nome,
        "isAuthPolExplicit": False,
        "isDiscoverable": True,
        "mangledTypeName": m,
        "mangledTypeNameByBundleIdentifier": {},
        "mangledTypeNameByBundleIdentifierV2": {},
        "mangledTypeNameV2": m,
        "openAppWhenRun": False,
        "outputFlags": 0,
        "parameters": [],
        "presentationStyle": 0,
        "requiredCapabilities": [],
        "supportedModes": 1,
        "systemProtocolMetadata": [
            PROTO_SESSIONE,
            {"empty": {}},
        ],
        "systemProtocolMetadataV2": [
            PROTO_SESSIONE,
            {"empty": {}},
        ],
        "systemProtocols": [
            PROTO_SESSIONE,
        ],
        "title": {
            "alternatives": [],
            "key": titolo,
        },
        "typeSpecificMetadata": [],
        "visibilityMetadata": {
            "assistantOnly": False,
            "isDiscoverable": True,
        },
    }


def scrivi_metadata(bundle_dir: pathlib.Path, modulo: str) -> None:
    meta_dir = bundle_dir / "Metadata.appintents"
    meta_dir.mkdir(parents=True, exist_ok=True)

    version_data = {
        "version": "3.0",
        "toolsVersion": "17C52",
    }
    (meta_dir / "version.json").write_text(
        json.dumps(version_data, indent=2) + "\n",
        encoding="utf-8",
    )

    actions = {
        nome: costruisci_azione(modulo, nome, titolo)
        for nome, titolo in INTENTI
    }
    extract_data = {
        "actions": actions,
        "assistantEntities": [],
        "assistantIntentNegativePhrases": [],
        "assistantIntents": [],
        "autoShortcutProviderMangledName": "",
        "autoShortcuts": [],
        "entities": {},
        "enums": [],
        "generator": {
            "name": "xcode-tools",
            "version": "17C52",
        },
        "negativePhrases": [],
        "queries": {},
        "shortcutTileColor": 14,
        "version": 1,
    }
    (meta_dir / "extract.actionsdata").write_text(
        json.dumps(extract_data, ensure_ascii=False, separators=(", ", ": ")),
        encoding="utf-8",
    )


def main() -> None:
    if len(sys.argv) < 2:
        print("Uso: genera_appintents.py <percorso/RecompNuova.app>", file=sys.stderr)
        sys.exit(1)

    app_dir = pathlib.Path(sys.argv[1])
    scrivi_metadata(app_dir, "RecompNuova")

    appex_dir = app_dir / "PlugIns" / "RecompLive.appex"
    if appex_dir.is_dir():
        scrivi_metadata(appex_dir, "RecompLive")


if __name__ == "__main__":
    main()
