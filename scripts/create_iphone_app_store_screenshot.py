from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSET_DIR = ROOT / "AppStoreAssets" / "iPhone"
SOURCE_PATH = ASSET_DIR / "vocaday-iphone-source.png"
ICON_PATH = ROOT / "VocaDay" / "Assets.xcassets" / "AppIcon.appiconset" / "vocaday-mac-512@2x.png"
OUTPUT_PATH = ASSET_DIR / "vocaday-iphone-1284x2778.png"

WIDTH = 1284
HEIGHT = 2778
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
    top = (7, 22, 49)
    bottom = (24, 67, 123)
    gradient = Image.new("RGB", (1, HEIGHT))
    pixels = gradient.load()
    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        pixels[0, y] = tuple(round(top[i] * (1 - t) + bottom[i] * t) for i in range(3))
    background = gradient.resize((WIDTH, HEIGHT)).convert("RGBA")

    glow = Image.new("RGBA", background.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse((-480, 420, 680, 1730), fill=(44, 148, 255, 78))
    glow_draw.ellipse((590, -550, 1580, 580), fill=(92, 111, 255, 66))
    glow_draw.ellipse((430, 1770, 1540, 2980), fill=(43, 207, 255, 42))
    glow = glow.filter(ImageFilter.GaussianBlur(190))
    return Image.alpha_composite(background, glow)


def draw_pill(canvas: Image.Image, xy: tuple[int, int], label: str) -> int:
    label_font = font(29, 4)
    draw = ImageDraw.Draw(canvas)
    box = draw.textbbox((0, 0), label, font=label_font)
    text_width = box[2] - box[0]
    x, y = xy
    pill_width = text_width + 72
    pill_height = 64

    overlay = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    overlay_draw = ImageDraw.Draw(overlay)
    overlay_draw.rounded_rectangle(
        (x, y, x + pill_width, y + pill_height),
        radius=32,
        fill=(255, 255, 255, 30),
        outline=(255, 255, 255, 50),
        width=2,
    )
    canvas.alpha_composite(overlay)
    draw = ImageDraw.Draw(canvas)
    draw.ellipse((x + 20, y + 25, x + 34, y + 39), fill=(117, 218, 255, 255))
    draw.text((x + 46, y + 14), label, font=label_font, fill=(239, 247, 255, 255))
    return pill_width


def main() -> None:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)
    canvas = make_background()
    draw = ImageDraw.Draw(canvas)

    icon = Image.open(ICON_PATH).convert("RGBA")
    icon.thumbnail((96, 96), Image.Resampling.LANCZOS)
    canvas.alpha_composite(icon, (86, 82))
    draw.text((204, 105), "VocaDay", font=font(43, 6), fill=(246, 250, 255, 255))

    draw.text((86, 245), "외울 단어를 한눈에,", font=font(82, 6), fill=(255, 255, 255, 255))
    draw.text((86, 350), "데이별로 차곡차곡", font=font(82, 6), fill=(135, 215, 255, 255))
    draw.text(
        (90, 485),
        "영단어와 뜻을 표로 정리하고 복습 기록까지 확인하세요.",
        font=font(31, 0),
        fill=(210, 228, 247, 255),
    )

    first_width = draw_pill(canvas, (88, 565), "데이별 단어 관리")
    draw_pill(canvas, (88 + first_width + 22, 565), "복습 횟수 확인")

    screenshot = Image.open(SOURCE_PATH).convert("RGB")
    target_width = 924
    target_height = round(screenshot.height * target_width / screenshot.width)
    screenshot = screenshot.resize((target_width, target_height), Image.Resampling.LANCZOS)
    screenshot = rounded_image(screenshot, 78)

    shot_x = (WIDTH - target_width) // 2
    shot_y = 690

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (shot_x - 16, shot_y + 24, shot_x + target_width + 16, shot_y + target_height + 48),
        radius=94,
        fill=(0, 0, 0, 175),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(42))
    canvas = Image.alpha_composite(canvas, shadow)
    canvas.alpha_composite(screenshot, (shot_x, shot_y))

    border_draw = ImageDraw.Draw(canvas)
    border_draw.rounded_rectangle(
        (shot_x, shot_y, shot_x + target_width - 1, shot_y + target_height - 1),
        radius=78,
        outline=(255, 255, 255, 64),
        width=3,
    )

    canvas.convert("RGB").save(OUTPUT_PATH, format="PNG", optimize=True)
    print(OUTPUT_PATH)


if __name__ == "__main__":
    main()
