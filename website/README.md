# Tapeek 官网

`tapeek.paymond.me` 的静态站点。纯 HTML/CSS，没有构建步骤；Cloudflare Workers 静态资源托管，免费额内。

## 目录

```
website/
├── cloudflare.config.ts   Worker 名称、静态资源、自定义域名
├── vite.config.ts         cf 构建入口（静态资源由 public/ 提供）
├── package.json
└── public/                部署内容
    ├── index.html         中文版（x-default）
    ├── en.html            英文版
    ├── styles.css         两版共用
    └── assets/            图标、截图、OG 图
```

## 本地预览

```sh
cd website
npm install
npm run dev        # cf dev
```

只想改页面时可以不起 dev server，直接开一个静态服务器：

```sh
cd website/public && python3 -m http.server 8000
```

## 部署

```sh
cd website
cf deploy
```

`cloudflare.config.ts` 里的 `domains` 已声明 `tapeek.paymond.me`，部署会同时更新 Worker 和自定义域名。首次部署会自动创建 DNS 记录和证书。

## 截图与图标

`public/assets/` 里的截图来自 `docs/verification/`，裁掉了 Quick Look 窗口标题栏，只保留内容区域：

| 文件 | 来源 |
| --- | --- |
| `md-dark.webp` | `T02-01-gfm-dark.png` |
| `md-light.webp` | `T05-01-front-matter-light.png` |
| `zip-dark.webp` | `T08-01-typical.png` |
| `icon-*.png` | `docs/assets/tapeek-icon.png` |
| `og.png` | 1200×630，中文版链接预览 |
| `og-en.png` | 1200×630，英文版链接预览 |

重新生成时用 `python3` + Pillow 裁剪（原始截图 1712×1378，内容区约 `62,112 - 1650,1312`），再按 1400 px 宽导出 WebP。

## 文案口径

- 性能数字取自 [`docs/verification/FINAL.md`](../docs/verification/FINAL.md)，不要在页面上写没有证据的指标。
- 限制一栏同时写在页面和 `FINAL.md` 的「已知限制」里，改一处时记得对另一处。
- 中英文两版内容一一对应，共用 `styles.css`。改文案、加章节、换截图时两版一起改，并同步 `hreflang` 与 OG 图。
