# m1ddc transport attribution

Source: https://github.com/waydabber/m1ddc
Pinned revision: 04d949794102eb8df01ad3681afff6464a3eede2
License: MIT, Copyright (c) 2021 waydabber. Full license preserved here and bundled in the app.

Only ioregistry.m, i2c.m and their headers are included. The app's brightness-only helper is maintained by Retina Dummy and validates DDC replies before use. Local modification: correct uint16_t read lengths in convertI2CtoDDC (sizeof(uint16_t) instead of sizeof(2)); the helper uses its own validated parser rather than that conversion function.

This transport uses private Apple APIs and supports Apple Silicon external-display connections with DDC/CI. Hardware, cable, port and OS compatibility may vary. Intel builds show an explicit unsupported message. No software dimming fallback is performed.
