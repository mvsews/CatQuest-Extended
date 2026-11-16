"""Draw simple original thumb silhouettes as 3.3.5-compatible RGBA TGA files."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps

root=Path(__file__).resolve().parents[1]
points=[(45,70),(58,55),(65,38),(65,18),(76,13),(86,20),(88,36),(83,59),
        (110,59),(119,66),(114,108),(106,118),(53,118),(45,110)]
preview=Image.new('RGBA',(80,40))
for name,color,down in [('VoteUp',(76,200,112,255),False),('VoteDown',(230,91,83,255),True)]:
    image=Image.new('RGBA',(128,128))
    draw=ImageDraw.Draw(image)
    draw.polygon(points,fill=color,outline=(237,242,226,255),width=5)
    draw.rounded_rectangle((13,70,39,118),radius=3,fill=color,outline=(237,242,226,255),width=5)
    if down:image=ImageOps.flip(ImageOps.mirror(image))
    image=image.resize((32,32),Image.Resampling.LANCZOS)
    image.save(root/'CatQuest'/f'{name}.tga')
    preview.alpha_composite(image,(44 if down else 4,4))
preview.save(root/'.tmp/vote-icons-preview.png')
