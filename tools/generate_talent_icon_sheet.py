from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "icons" / "talents"
SHEET_PATH = OUT_DIR / "talent_icons_sheet.png"
MANIFEST_PATH = OUT_DIR / "talent_icons_sheet_manifest.json"

CELL = 64
COLS = 8
ROWS = 5
BG = (255, 0, 255, 255)

PALETTE = {
    "outline": (25, 19, 16, 255),
    "shadow": (50, 43, 35, 255),
    "steel": (132, 142, 144, 255),
    "steel_dark": (75, 87, 92, 255),
    "bone": (222, 212, 176, 255),
    "gold": (218, 157, 51, 255),
    "gold_light": (250, 209, 92, 255),
    "rust": (152, 58, 39, 255),
    "red": (177, 49, 41, 255),
    "green": (71, 128, 70, 255),
    "green_light": (119, 178, 86, 255),
    "blue": (76, 148, 184, 255),
    "blue_light": (141, 205, 220, 255),
    "brown": (117, 75, 43, 255),
    "leather": (151, 97, 51, 255),
    "parchment": (203, 177, 114, 255),
    "white": (236, 231, 204, 255),
}

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


def c(name: str) -> tuple[int, int, int, int]:
    return PALETTE[name]


def rect(d: ImageDraw.ImageDraw, xy, fill: str, outline: str = "outline", width: int = 3) -> None:
    d.rectangle(xy, fill=c(fill), outline=c(outline), width=width)


def ell(d: ImageDraw.ImageDraw, xy, fill: str, outline: str = "outline", width: int = 3) -> None:
    d.ellipse(xy, fill=c(fill), outline=c(outline), width=width)


def poly(d: ImageDraw.ImageDraw, pts, fill: str, outline: str = "outline") -> None:
    d.polygon(pts, fill=c(fill), outline=c(outline))


def line(d: ImageDraw.ImageDraw, pts, fill: str = "outline", width: int = 4) -> None:
    d.line(pts, fill=c(fill), width=width, joint="curve")


def sword(d: ImageDraw.ImageDraw, x: int = 33, y: int = 31, scale: int = 1) -> None:
    poly(d, [(x, y - 25), (x + 6, y - 5), (x, y + 17), (x - 6, y - 5)], "steel")
    rect(d, (x - 13, y + 10, x + 13, y + 16), "gold")
    rect(d, (x - 4, y + 15, x + 4, y + 28), "leather")
    d.rectangle((x - 2, y - 17, x + 2, y + 7), fill=c("steel_dark"))


def shield(d: ImageDraw.ImageDraw, x: int = 32, y: int = 31, fill: str = "steel") -> None:
    poly(d, [(x - 18, y - 20), (x + 18, y - 20), (x + 16, y + 6), (x, y + 24), (x - 16, y + 6)], fill)
    line(d, [(x, y - 17), (x, y + 18)], "gold", 3)


def coin(d: ImageDraw.ImageDraw, x: int, y: int, r: int = 9) -> None:
    ell(d, (x - r, y - r, x + r, y + r), "gold", "outline", 2)
    d.rectangle((x - 2, y - r + 3, x + 2, y + r - 3), fill=c("gold_light"))


def boot(d: ImageDraw.ImageDraw, x: int, y: int) -> None:
    rect(d, (x - 10, y - 17, x + 5, y + 8), "leather")
    rect(d, (x - 10, y + 4, x + 18, y + 13), "brown")


def draw_icon(d: ImageDraw.ImageDraw, key: str) -> None:
    # Small dark backing tile keeps the icons readable on the magenta key.
    rect(d, (7, 7, 56, 56), "shadow", "outline", 2)

    if key == "gear_sharper_eye":
        ell(d, (13, 21, 51, 43), "bone")
        ell(d, (25, 23, 39, 41), "blue")
        ell(d, (29, 27, 35, 37), "outline", "outline", 1)
        line(d, [(44, 16), (52, 9)], "gold", 3)
    elif key == "gear_set_seeker":
        for x, y, fill in [(22, 20, "steel"), (40, 21, "green"), (31, 39, "gold")]:
            poly(d, [(x, y - 12), (x + 11, y), (x, y + 12), (x - 11, y)], fill)
    elif key.endswith("_quality"):
        fill = {"gear_awakened_quality": "blue", "gear_ascendant_quality": "green", "gear_transcendent_quality": "white"}[key]
        poly(d, [(32, 9), (50, 28), (42, 53), (22, 53), (14, 28)], fill)
        line(d, [(32, 10), (32, 51)], "gold", 3)
        line(d, [(16, 28), (48, 28)], "gold_light", 2)
    elif key == "gear_salvage_mastery":
        rect(d, (16, 35, 49, 45), "steel")
        line(d, [(19, 19), (45, 45)], "gold", 5)
        line(d, [(45, 19), (19, 45)], "rust", 5)
    elif key == "buildings_efficient_construction":
        rect(d, (16, 30, 45, 48), "brown")
        poly(d, [(12, 31), (31, 14), (50, 31)], "rust")
        line(d, [(43, 14), (52, 23)], "steel", 5)
    elif key == "buildings_expanded_lots":
        for box in [(13, 15, 28, 30), (36, 15, 51, 30), (24, 36, 39, 51)]:
            rect(d, box, "green")
    elif key == "buildings_reinforced_towers":
        rect(d, (21, 21, 43, 53), "steel")
        rect(d, (17, 13, 47, 25), "steel_dark")
        line(d, [(22, 38), (42, 38)], "gold", 3)
    elif key == "buildings_wider_reach":
        ell(d, (9, 9, 55, 55), "green", "outline", 2)
        ell(d, (19, 19, 45, 45), "shadow", "gold", 3)
        rect(d, (28, 28, 36, 36), "gold")
    elif key == "buildings_fortified_walls":
        for x in [13, 28, 43]:
            rect(d, (x, 22, x + 11, 49), "steel")
        rect(d, (12, 35, 55, 51), "steel_dark")
    elif key == "recruiting_talent_scout":
        ell(d, (15, 18, 49, 42), "green")
        ell(d, (26, 22, 38, 38), "gold")
        line(d, [(41, 42), (51, 53)], "leather", 4)
    elif key == "recruiting_pick_of_the_litter":
        for x in [17, 32]:
            shield(d, x, 32, "steel")
    elif key == "recruiting_cream_of_the_crop":
        for x, y in [(19, 31), (32, 23), (45, 31)]:
            ell(d, (x - 8, y - 8, x + 8, y + 8), "gold", "outline", 2)
            rect(d, (x - 5, y + 5, x + 5, y + 20), "steel")
    elif key == "recruiting_veteran_enrollment":
        shield(d, 30, 32, "green")
        line(d, [(42, 16), (50, 8)], "gold", 3)
        line(d, [(46, 8), (50, 8), (50, 12)], "gold", 3)
    elif key == "combat_hardened_ranks":
        shield(d, 32, 31, "steel")
        rect(d, (17, 25, 47, 33), "gold")
    elif key == "combat_sharpened_blades":
        sword(d, 24, 31)
        sword(d, 42, 31)
    elif key == "combat_forced_march":
        boot(d, 25, 36)
        line(d, [(42, 20), (53, 20), (48, 15)], "gold_light", 3)
        line(d, [(42, 28), (53, 28), (48, 33)], "gold_light", 3)
    elif key == "combat_heros_resolve":
        shield(d, 31, 32, "red")
        sword(d, 43, 30)
    elif key == "combat_veterans_grit":
        shield(d, 32, 32, "steel")
        for x in [22, 32, 42]:
            line(d, [(x, 17), (x + 4, 24)], "gold", 2)
    elif key == "combat_last_stand":
        sword(d, 32, 32)
        rect(d, (16, 42, 48, 49), "red")
    elif key == "economy_bountiful_harvest":
        line(d, [(32, 47), (32, 18)], "green", 4)
        for p in [[(32, 23), (16, 14), (20, 32)], [(32, 29), (48, 18), (45, 37)], [(32, 37), (18, 32), (23, 48)]]:
            poly(d, p, "green_light")
    elif key == "economy_steady_coffers":
        rect(d, (15, 27, 49, 49), "brown")
        rect(d, (20, 18, 44, 30), "leather")
        coin(d, 32, 36, 8)
    elif key == "economy_trade_routes":
        line(d, [(13, 46), (26, 28), (39, 35), (51, 17)], "parchment", 4)
        for x, y in [(13, 46), (26, 28), (39, 35), (51, 17)]:
            coin(d, x, y, 5)
    elif key == "economy_guild_contracts":
        rect(d, (18, 14, 45, 50), "parchment")
        line(d, [(24, 25), (39, 25)], "outline", 2)
        line(d, [(24, 33), (37, 33)], "outline", 2)
        coin(d, 45, 45, 7)
    elif key == "economy_supply_network":
        for x, y in [(17, 19), (46, 19), (32, 47)]:
            coin(d, x, y, 7)
        line(d, [(17, 19), (46, 19), (32, 47), (17, 19)], "green_light", 3)
    elif key == "diplomatic_tongue":
        ell(d, (15, 17, 49, 43), "parchment")
        poly(d, [(25, 42), (19, 52), (35, 43)], "parchment")
        line(d, [(24, 30), (40, 30)], "outline", 2)
    elif key == "toggle_invasions":
        ell(d, (14, 14, 50, 50), "green")
        line(d, [(20, 40), (44, 18)], "bone", 4)
        line(d, [(20, 18), (44, 40)], "bone", 4)
    elif key == "dungeon_extended_campaign":
        rect(d, (19, 14, 45, 50), "parchment")
        line(d, [(25, 22), (39, 22)], "gold", 2)
        line(d, [(24, 32), (40, 32)], "red", 3)
    elif key == "dungeon_marathon_runner":
        boot(d, 30, 39)
        line(d, [(17, 17), (48, 17)], "gold_light", 3)
        line(d, [(42, 12), (49, 17), (42, 22)], "gold_light", 3)
    elif key == "dungeon_loaded_dice":
        rect(d, (16, 18, 36, 38), "bone")
        rect(d, (31, 28, 51, 48), "bone")
        for x, y in [(23, 25), (30, 32), (39, 36), (45, 42)]:
            d.rectangle((x - 1, y - 1, x + 1, y + 1), fill=c("outline"))
    elif key == "dungeon_quick_study":
        rect(d, (18, 16, 46, 50), "parchment")
        line(d, [(31, 16), (31, 50)], "outline", 2)
        line(d, [(39, 19), (49, 12)], "gold_light", 3)
    elif key == "dungeon_skill_mastery":
        for x, y in [(21, 22), (43, 22), (21, 44), (43, 44)]:
            ell(d, (x - 8, y - 8, x + 8, y + 8), "blue")
        line(d, [(21, 22), (43, 44), (43, 22), (21, 44)], "gold", 2)
    elif key == "dungeon_opening_gambit":
        poly(d, [(16, 42), (32, 12), (48, 42)], "gold")
        line(d, [(23, 36), (41, 36)], "red", 3)
    elif key == "dungeon_veteran_commander":
        shield(d, 32, 31, "steel")
        rect(d, (23, 12, 41, 20), "gold")
    elif key == "dungeon_relentless":
        ell(d, (18, 18, 46, 46), "red")
        line(d, [(32, 15), (32, 49)], "white", 5)
        line(d, [(20, 32), (44, 32)], "white", 5)
    elif key == "dungeon_iron_will":
        shield(d, 32, 32, "steel_dark")
        line(d, [(20, 44), (44, 20)], "gold_light", 5)
    elif key == "dungeon_combat_drilling":
        rect(d, (16, 38, 49, 48), "brown")
        line(d, [(20, 21), (46, 21)], "steel", 4)
        line(d, [(25, 15), (25, 36)], "steel", 4)
        line(d, [(40, 15), (40, 36)], "steel", 4)
    elif key == "dungeon_treasure_hunter":
        rect(d, (15, 25, 49, 49), "brown")
        coin(d, 31, 35, 10)
        line(d, [(41, 19), (51, 11)], "gold_light", 3)
    elif key == "dungeon_spoils":
        rect(d, (15, 30, 49, 50), "leather")
        for x, y in [(24, 28), (34, 25), (43, 30)]:
            coin(d, x, y, 6)
    else:
        ell(d, (18, 18, 46, 46), "gold")

    # Pixel glints in safe colors.
    d.rectangle((12, 12, 14, 14), fill=c("gold_light"))
    d.rectangle((49, 49, 51, 51), fill=c("outline"))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (COLS * CELL, ROWS * CELL), BG)
    manifest = {
        "sheet": "res://assets/icons/talents/talent_icons_sheet.png",
        "cell_size": CELL,
        "columns": COLS,
        "background": "#FF00FF",
        "order": [],
    }

    for index, (key, name) in enumerate(TALENTS):
        col = index % COLS
        row = index // COLS
        icon = Image.new("RGBA", (CELL, CELL), BG)
        draw_icon(ImageDraw.Draw(icon), key)
        sheet.alpha_composite(icon, (col * CELL, row * CELL))
        manifest["order"].append(
            {
                "id": key,
                "name": name,
                "index": index,
                "row": row,
                "column": col,
                "rect": [col * CELL, row * CELL, CELL, CELL],
            }
        )

    sheet.save(SHEET_PATH)
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(SHEET_PATH)
    print(MANIFEST_PATH)


if __name__ == "__main__":
    main()
