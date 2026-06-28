from __future__ import annotations

import json
from pathlib import Path

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "icons" / "reference_sheets" / "fantasy_icon_reference_green_bg.png"
OUT_DIR = ROOT / "assets" / "icons" / "talents" / "reference"
MANIFEST_PATH = OUT_DIR / "manifest.json"
PREVIEW_PATH = OUT_DIR / "preview.png"

COLS = 8
ROWS = 5
CANVAS = 96
GREEN = (0, 255, 0, 255)

TALENTS = [
    ("gear_sharper_eye", "Sharper Eye"),
    ("gear_set_seeker", "Set Seeker"),
    ("gear_awakened_quality", "Awakened Quality"),
    ("gear_ascendant_quality", "Ascendant Quality"),
    ("gear_transcendent_quality", "Transcendent Quality"),
    ("gear_salvage_mastery", "Salvage Mastery"),
    ("buildings_efficient_construction", "Efficient Construction"),
    ("buildings_expanded_lots", "Expanded Lots"),
    ("buildings_reinforced_towers", "Reinforced Towers"),
    ("buildings_wider_reach", "Wider Reach"),
    ("buildings_fortified_walls", "Fortified Walls"),
    ("recruiting_talent_scout", "Talent Scout"),
    ("recruiting_pick_of_the_litter", "Pick of the Litter"),
    ("recruiting_cream_of_the_crop", "Cream of the Crop"),
    ("recruiting_veteran_enrollment", "Veteran Enrollment"),
    ("combat_hardened_ranks", "Hardened Ranks"),
    ("combat_sharpened_blades", "Sharpened Blades"),
    ("combat_forced_march", "Forced March"),
    ("combat_heros_resolve", "Hero's Resolve"),
    ("combat_veterans_grit", "Veterans' Grit"),
    ("combat_last_stand", "Last Stand"),
    ("economy_bountiful_harvest", "Bountiful Harvest"),
    ("economy_steady_coffers", "Steady Coffers"),
    ("economy_trade_routes", "Trade Routes"),
    ("economy_guild_contracts", "Guild Contracts"),
    ("economy_supply_network", "Supply Network"),
    ("diplomatic_tongue", "Diplomatic Tongue"),
    ("toggle_invasions", "Wilds Pact"),
    ("dungeon_extended_campaign", "Extended Campaign"),
    ("dungeon_marathon_runner", "Marathon Runner"),
    ("dungeon_loaded_dice", "Loaded Dice"),
    ("dungeon_quick_study", "Quick Study"),
    ("dungeon_skill_mastery", "Skill Mastery"),
    ("dungeon_opening_gambit", "Opening Gambit"),
    ("dungeon_veteran_commander", "Veteran Commander"),
    ("dungeon_relentless", "Relentless"),
    ("dungeon_iron_will", "Iron Will"),
    ("dungeon_combat_drilling", "Combat Drilling"),
    ("dungeon_treasure_hunter", "Treasure Hunter"),
    ("dungeon_spoils", "Dungeon Spoils"),
]


def is_key(pixel: tuple[int, int, int, int]) -> bool:
    r, g, b, a = pixel
    return a == 0 or (g >= 220 and r <= 60 and b <= 60)


def content_bounds(image: Image.Image) -> tuple[int, int, int, int]:
    px = image.load()
    min_x, min_y = image.width, image.height
    max_x, max_y = -1, -1
    for y in range(image.height):
        for x in range(image.width):
            if not is_key(px[x, y]):
                min_x = min(min_x, x)
                min_y = min(min_y, y)
                max_x = max(max_x, x)
                max_y = max(max_y, y)
    if max_x < min_x or max_y < min_y:
        return (0, 0, image.width, image.height)
    pad = 3
    return (
        max(0, min_x - pad),
        max(0, min_y - pad),
        min(image.width, max_x + pad + 1),
        min(image.height, max_y + pad + 1),
    )


def remove_key(image: Image.Image) -> Image.Image:
    out = Image.new("RGBA", image.size, (0, 0, 0, 0))
    src = image.load()
    dst = out.load()
    for y in range(image.height):
        for x in range(image.width):
            pixel = src[x, y]
            if not is_key(pixel):
                dst[x, y] = pixel
    return out


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    source = Image.open(SOURCE).convert("RGBA")
    cell_w = source.width / COLS
    cell_h = source.height / ROWS
    manifest = {
        "source": "res://assets/icons/reference_sheets/fantasy_icon_reference_green_bg.png",
        "output_dir": "res://assets/icons/talents/reference",
        "canvas_size": CANVAS,
        "order": [],
    }
    preview = Image.new("RGBA", (COLS * CANVAS, ROWS * CANVAS), (38, 36, 32, 255))

    for index, (talent_id, name) in enumerate(TALENTS):
        col = index % COLS
        row = index // COLS
        x0 = round(col * cell_w)
        y0 = round(row * cell_h)
        x1 = round((col + 1) * cell_w)
        y1 = round((row + 1) * cell_h)
        cell = source.crop((x0, y0, x1, y1))
        cropped = remove_key(cell.crop(content_bounds(cell)))
        cropped.thumbnail((CANVAS - 8, CANVAS - 8), Image.Resampling.LANCZOS)
        icon = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
        pos = ((CANVAS - cropped.width) // 2, (CANVAS - cropped.height) // 2)
        icon.alpha_composite(cropped, pos)
        path = OUT_DIR / f"{talent_id}.png"
        icon.save(path)
        preview.alpha_composite(icon, (col * CANVAS, row * CANVAS))
        manifest["order"].append({
            "id": talent_id,
            "name": name,
            "path": f"res://assets/icons/talents/reference/{talent_id}.png",
            "row": row,
            "column": col,
        })

    preview.save(PREVIEW_PATH)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(OUT_DIR)
    print(PREVIEW_PATH)
    print(MANIFEST_PATH)


if __name__ == "__main__":
    main()
