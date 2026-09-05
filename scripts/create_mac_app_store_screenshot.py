from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "AppStoreAssets" / "macOS"
SOURCE_PATH = ASSET_DIR / "vocaday-macos-source.jpeg"
ICON_PATH = ROOT / "VocaDay" / "Assets.xcassets" / "AppIcon.appiconset" / "vocaday-mac-512@2x.png"
OUTPUT_PATH = ASSET_DIR / "vocaday-macos-1440x900.png"

WIDTH = 1440
HEIGHT = 900
FONT_PATH = "/System/Library/Fonts/AppleSDGothicNeo.ttc"


def font(size: int, index: int = 0) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(FONT_PATH, size=size, index=index)


def rounded_image(image: Image.Image, radius: int) -> Image.Image:
    image = image.convert("RGBA")
    mask = Image.new("L", image.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle((0, 0, image.width - 1, image.height - 1), radius=radius, fill=255)
    image.putalpha(mask)
    return image


def make_background() -> Image.Image:
    top = (8, 22, 47)
    bottom = (27, 62, 111)
    gradient = Image.new("RGB", (1, HEIGHT))
    pixels = gradient.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        pixels[0, y] = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    background = gradient.resize((WIDTH, HEIGHT)).convert("RGBA")

    glow = Image.new("RGBA", background.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-260, 390, 560, 1210), fill=(45, 144, 255, 76))
    glow_draw.ellipse((780, -380, 1650, 470), fill=(71, 121, 255, 58))
    glow = glow.filter(ImageFilter.GaussianBlur(125))
    return Image.alpha_composite(background, glow)


def draw_pill(canvas: Image.Image, xy: tuple[int, int], label: str) -> None:
    label_font = font(22, 4)
    draw = ImageDraw.Draw(canvas)
    box = draw.textbbox((0, 0), label, font=label_font)
    text_width = box[2] - box[0]
    x, y = xy
    pill_width = text_width + 62
    pill_height = 52
    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.rounded_rectangle(
        (x, y, x + pill_width, y + pill_height),
        radius=26,
        fill=(255, 255, 255, 30),
        outline=(255, 255, 255, 48),
        width=1,
    )
    canvas.alpha_composite(overlay)
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((x + 18, y + 20, x + 30, y + 32), fill=(123, 211, 255, 255))
    draw.text((x + 40, y + 12), label, font=label_font, fill=(235, 245, 255, 255))


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    canvas = make_background()
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON_PATH).convert("RGBA")
    icon.thumbnail((72, 72), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, (82, 64))
    draw.text((169, 81), "VocaDay", font=font(29, 6), fill=(245, 249, 255, 255))

    draw.text((82, 203), "매일의 단어를", font=font(64, 6), fill=(255, 255, 255, 255))
    draw.text((82, 285), "나만의 데이로", font=font(64, 6), fill=(137, 211, 255, 255))

    subhead = "단어를 데이별로 정리하고\n복습 기록까지 한눈에 확인하세요."
    draw.multiline_text(
        (84, 402),
        subhead,
        font=font(27, 0),
        fill=(210, 226, 244, 255),
        spacing=13,
    )

    draw_pill(canvas, (82, 533), "데이별 단어 관리")
    draw_pill(canvas, (82, 602), "복습 기록 확인")
    draw.text(
        (84, 754),
        "iPhone과 Mac에서 이어지는 영어 학습",
        font=font(20, 2),
        fill=(172, 198, 226, 255),
    )

    screenshot = Image.open(SOURCE_PATH).convert("RGB")
    target_width = 742
    target_height = round(screenshot.height * target_width / screenshot.width)
    screenshot = screenshot.resize((target_width, target_height), Image.Resampling.LANCZOS)
    screenshot = rounded_image(screenshot, 26)

    shot_x = 650
    shot_y = (HEIGHT - target_height) // 2
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (shot_x - 7, shot_y + 12, shot_x + target_width + 7, shot_y + target_height + 24),
        radius=34,
        fill=(0, 0, 0, 150),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(24))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(screenshot, (shot_x, shot_y))

    border_draw = ImageDraw.Draw(canvas)
    border_draw.rounded_rectangle(
        (shot_x, shot_y, shot_x + target_width - 1, shot_y + target_height - 1),
        radius=26,
        outline=(255, 255, 255, 50),
        width=2,
    )

    canvas.convert("RGB").save(OUTPUT_PATH, format="PNG", optimize=True)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
