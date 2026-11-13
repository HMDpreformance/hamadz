# Generated textures (0.9.0)

All made with Higgsfield `gpt_image_2_6` on 2026-11-12 from text prompts only (no reference images, no brands or logos). About 5 credits in total.

| File | Use | Source |
| --- | --- | --- |
| `textures/showroom_backdrop.jpg` | Car Lot background; its floor is re-projected in 3D (`showroom.gd`) so cars reflect and cast shadows | 16:9, 2k, high quality, resized to 1920x1080 |
| `textures/garage_pano.jpg` | 360 workshop for the Garage background and for car reflections everywhere indoors (`EnvKit.photo_sky`, bright tubes boosted in the sky shader) | 21:9, 2k, stretched to 2048x1024 |
| `textures/concrete.jpg` | Garage floor | 1k tile, made seamless with an offset blend |
| `textures/brick.jpg` | Brick walls (modelled garage room, kept as fallback) | 1k tile, seamless |
| `textures/asphalt.jpg` | City and expressway road surface | 1k tile, seamless |

Import settings: tiles and the panorama are VRAM compressed with mipmaps (ETC2/ASTC on Android); the backdrop is lossy WebP.
