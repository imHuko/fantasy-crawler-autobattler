from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw


ROOT = Path(__file__).resolve().parents[1]
OUT_DIR = ROOT / "assets" / "icons" / "action_skills"
SHEET_PATH = OUT_DIR / "action_skill_icons_sprite_style_sheet.png"
MANIFEST_PATH = OUT_DIR / "action_skill_icons_sprite_style_manifest.json"

CELL = 64
COLS = 6
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
    "orange": (214, 102, 38, 255),
}

SKILLS = [
    ("swiftness", "Swiftness"),
    ("iron_hide", "Iron Hide"),
    ("armor_plating", "Armor Plating"),
    ("rapid_fire", "Rapid Fire"),
    ("power_shot", "Power Shot"),
    ("deadly_crits", "Deadly Crits"),
    ("crushing_blow", "Crushing Blow"),
    ("wide_range", "Wide Range"),
    ("glass_cannon", "Glass Cannon"),
    ("lucky", "Lucky"),
    ("vampiric", "Vampiric"),
    ("multishot", "Multishot"),
    ("piercing", "Piercing Shot"),
    ("explosive", "Explosive Rounds"),
    ("orb_shield", "Orbital Shield"),
    ("nova_burst", "Nova Burst"),
    ("death_rattle", "Death Rattle"),
    ("berserker", "Berserker"),
    ("second_wind", "Second Wind"),
    ("lifesteal", "Lifesteal"),
    ("plunder", "Plunder"),
    ("chain_lightning", "Chain Lightning"),
    ("burning_ground", "Burning Ground"),
    ("guardian_wisp", "Guardian Wisp"),
    ("greed_curse", "Greed Curse"),
    ("heavy_draw", "Heavy Draw"),
    ("arcane_echo", "Arcane Echo"),
    ("knights_wake", "Knight's Wake"),
    ("healing_pulse", "Healing Pulse"),
    ("rogue_mark", "Rogue Mark"),
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


def arrow(d: ImageDraw.ImageDraw, x1: int, y1: int, x2: int, y2: int, fill: str = "bone") -> None:
    line(d, [(x1, y1), (x2, y2)], "leather", 4)
    poly(d, [(x2, y2), (x2 - 9, y2 - 5), (x2 - 6, y2 + 5)], fill)
    line(d, [(x1, y1), (x1 + 6, y1 - 5)], "red", 2)
    line(d, [(x1, y1), (x1 + 7, y1 + 4)], "red", 2)


def sword(d: ImageDraw.ImageDraw, x: int = 32, y: int = 32) -> None:
    poly(d, [(x, y - 24), (x + 6, y - 5), (x, y + 15), (x - 6, y - 5)], "steel")
    rect(d, (x - 12, y + 10, x + 12, y + 16), "gold")
    rect(d, (x - 4, y + 15, x + 4, y + 27), "leather")


def shield(d: ImageDraw.ImageDraw, x: int = 32, y: int = 32, fill: str = "steel") -> None:
    poly(d, [(x - 18, y - 20), (x + 18, y - 20), (x + 16, y + 6), (x, y + 24), (x - 16, y + 6)], fill)
    line(d, [(x, y - 17), (x, y + 18)], "gold", 3)


def coin(d: ImageDraw.ImageDraw, x: int, y: int, r: int = 8) -> None:
    ell(d, (x - r, y - r, x + r, y + r), "gold", "outline", 2)
    d.rectangle((x - 2, y - r + 3, x + 2, y + r - 3), fill=c("gold_light"))


def heart(d: ImageDraw.ImageDraw, x: int, y: int, fill: str = "red") -> None:
    ell(d, (x - 15, y - 11, x - 1, y + 3), fill, "outline", 2)
    ell(d, (x + 1, y - 11, x + 15, y + 3), fill, "outline", 2)
    poly(d, [(x - 15, y - 2), (x + 15, y - 2), (x, y + 19)], fill)


def boot(d: ImageDraw.ImageDraw, x: int, y: int) -> None:
    rect(d, (x - 10, y - 17, x + 5, y + 8), "leather")
    rect(d, (x - 10, y + 4, x + 18, y + 13), "brown")


def draw_icon(d: ImageDraw.ImageDraw, key: str) -> None:
    # Free-standing sprite style: no UI tile/backing, just a small ground
    # shadow like the troop/enemy sheets.
    d.ellipse((16, 47, 50, 57), fill=c("outline"))

    if key == "swiftness":
        boot(d, 27, 37)
        line(d, [(41, 18), (54, 18), (49, 13)], "gold_light", 3)
        line(d, [(42, 27), (55, 27), (50, 32)], "gold_light", 3)
    elif key == "iron_hide":
        shield(d, 32, 32, "steel_dark")
        rect(d, (19, 26, 45, 38), "steel")
    elif key == "armor_plating":
        for y in [16, 29, 42]:
            rect(d, (16, y, 48, y + 9), "steel")
    elif key == "rapid_fire":
        for y in [20, 32, 44]:
            arrow(d, 13, y, 49, y)
    elif key == "power_shot":
        arrow(d, 13, 40, 51, 22, "gold_light")
        ell(d, (39, 12, 55, 28), "orange", "outline", 2)
    elif key == "deadly_crits":
        ell(d, (15, 15, 49, 49), "steel_dark")
        line(d, [(20, 32), (44, 32)], "red", 4)
        line(d, [(32, 20), (32, 44)], "red", 4)
    elif key == "crushing_blow":
        rect(d, (18, 31, 48, 47), "steel_dark")
        rect(d, (26, 15, 39, 32), "leather")
        line(d, [(18, 48), (12, 54)], "orange", 3)
    elif key == "wide_range":
        ell(d, (10, 10, 54, 54), "green", "outline", 2)
        ell(d, (20, 20, 44, 44), "shadow", "gold", 3)
        arrow(d, 20, 42, 46, 18)
    elif key == "glass_cannon":
        poly(d, [(32, 10), (45, 43), (32, 54), (19, 43)], "blue_light")
        line(d, [(23, 22), (42, 41)], "red", 3)
        line(d, [(42, 22), (23, 41)], "red", 3)
    elif key == "lucky":
        for x, y in [(24, 24), (42, 27), (31, 43)]:
            coin(d, x, y, 7)
    elif key == "vampiric":
        heart(d, 32, 27)
        poly(d, [(22, 41), (28, 53), (34, 41)], "bone")
        poly(d, [(34, 41), (40, 53), (46, 41)], "bone")
    elif key == "multishot":
        arrow(d, 13, 20, 49, 20)
        arrow(d, 13, 32, 51, 32)
        arrow(d, 13, 44, 49, 44)
    elif key == "piercing":
        arrow(d, 12, 33, 53, 33, "steel")
        for x in [24, 35, 46]:
            rect(d, (x - 3, 25, x + 3, 41), "red")
    elif key == "explosive":
        ell(d, (22, 22, 42, 42), "orange")
        for pts in [[(32, 9), (36, 22), (28, 22)], [(32, 55), (36, 42), (28, 42)], [(9, 32), (22, 28), (22, 36)], [(55, 32), (42, 28), (42, 36)]]:
            poly(d, pts, "gold_light")
    elif key == "orb_shield":
        shield(d, 32, 32, "steel")
        for x, y in [(18, 18), (46, 18), (18, 46), (46, 46)]:
            ell(d, (x - 5, y - 5, x + 5, y + 5), "blue_light", "outline", 1)
    elif key == "nova_burst":
        ell(d, (22, 22, 42, 42), "blue")
        for x1, y1, x2, y2 in [(32, 9, 32, 20), (32, 44, 32, 55), (9, 32, 20, 32), (44, 32, 55, 32), (16, 16, 24, 24), (48, 16, 40, 24), (16, 48, 24, 40), (48, 48, 40, 40)]:
            line(d, [(x1, y1), (x2, y2)], "gold_light", 3)
    elif key == "death_rattle":
        ell(d, (20, 14, 44, 41), "bone")
        rect(d, (25, 39, 39, 49), "bone")
        line(d, [(18, 49), (46, 49)], "orange", 3)
    elif key == "berserker":
        sword(d, 24, 33)
        sword(d, 43, 33)
        line(d, [(17, 15), (47, 15)], "red", 5)
    elif key == "second_wind":
        heart(d, 31, 27)
        line(d, [(17, 46), (31, 54), (47, 43)], "green_light", 4)
    elif key == "lifesteal":
        sword(d, 32, 31)
        heart(d, 43, 43, "red")
    elif key == "plunder":
        rect(d, (15, 27, 49, 49), "brown")
        coin(d, 31, 36, 9)
        line(d, [(43, 16), (51, 9)], "red", 3)
    elif key == "chain_lightning":
        line(d, [(18, 13), (34, 28), (26, 29), (47, 51)], "gold_light", 5)
        ell(d, (11, 10, 23, 22), "blue")
        ell(d, (41, 44, 53, 56), "blue")
    elif key == "burning_ground":
        rect(d, (16, 43, 48, 51), "brown")
        for x in [22, 32, 42]:
            poly(d, [(x, 18), (x + 8, 43), (x, 50), (x - 8, 43)], "orange")
            poly(d, [(x, 29), (x + 4, 43), (x, 47), (x - 4, 43)], "gold_light")
    elif key == "guardian_wisp":
        ell(d, (21, 17, 43, 39), "blue_light")
        ell(d, (26, 22, 38, 34), "white", "blue", 2)
        line(d, [(32, 39), (25, 50), (38, 50), (32, 39)], "blue_light", 3)
    elif key == "greed_curse":
        coin(d, 32, 32, 13)
        line(d, [(20, 18), (44, 46)], "red", 4)
        line(d, [(44, 18), (20, 46)], "red", 4)
    elif key == "heavy_draw":
        line(d, [(18, 13), (18, 51)], "leather", 5)
        line(d, [(18, 13), (43, 32), (18, 51)], "bone", 3)
        arrow(d, 17, 32, 52, 32, "steel")
    elif key == "arcane_echo":
        ell(d, (17, 17, 47, 47), "blue", "outline", 2)
        ell(d, (23, 23, 53, 53), "blue_light", "outline", 2)
        ell(d, (25, 25, 39, 39), "white", "outline", 1)
    elif key == "knights_wake":
        sword(d, 28, 29)
        line(d, [(15, 49), (32, 43), (50, 49)], "steel", 4)
    elif key == "healing_pulse":
        heart(d, 32, 31)
        line(d, [(32, 13), (32, 49)], "white", 4)
        line(d, [(14, 31), (50, 31)], "white", 4)
    elif key == "rogue_mark":
        ell(d, (15, 15, 49, 49), "steel_dark")
        line(d, [(22, 42), (42, 22)], "bone", 5)
        line(d, [(21, 22), (43, 43)], "red", 3)
    else:
        ell(d, (18, 18, 46, 46), "gold")

    # A few tiny dark foot pixels help the objects feel grounded without
    # turning them into framed UI badges.
    d.rectangle((24, 53, 27, 55), fill=c("outline"))
    d.rectangle((38, 53, 41, 55), fill=c("outline"))


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    sheet = Image.new("RGBA", (COLS * CELL, ROWS * CELL), BG)
    manifest = {
        "sheet": "res://assets/icons/action_skills/action_skill_icons_sprite_style_sheet.png",
        "cell_size": CELL,
        "columns": COLS,
        "background": "#FF00FF",
        "order": [],
    }

    for index, (key, name) in enumerate(SKILLS):
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
