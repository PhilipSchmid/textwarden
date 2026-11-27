# TextWarden website

The landing page lives in `docs/index.html`. GitHub Pages can serve the `docs` directory directly. It includes the screenshot gallery, fonts, styles, and JavaScript. The existing Mac download badge links to the latest GitHub release. Updating the release requires no website edits.

## Preview locally

From the repository root, run `python3 -m http.server 8000 --bind 127.0.0.1 --directory docs` and open [the local preview](http://127.0.0.1:8000). Open the Apple Mail screenshot in the hero, then check the feature tabs (including AI Compose and Sketch Pad) and the mobile layout. Open a screenshot, toggle Actual size, and press Escape to return to the gallery. Under Customize TextWarden, expand the toolbar and suggestion menus and switch between the pill positions and the open style suggestion. Disable JavaScript to read the feature tabs in sequence and use the native customization controls.

## Publish on the two domains

1. Verify ownership of `textwarden.io` in the GitHub account’s Pages settings using the provided TXT record. Select **Deploy from a branch → main → /docs** under **Settings → Pages** in this repository. Confirm the custom domain is `textwarden.io`, matching `docs/CNAME`. [GitHub domain verification](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/verifying-your-custom-domain-for-github-pages)
2. In the Cloudflare zone for `textwarden.io`, configure the apex (`@`) with four **DNS only** A records, one each for `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, and `185.199.111.153`. Check for conflicting apex address records. Once GitHub verifies DNS and provisions the certificate, enable **Enforce HTTPS** in Pages settings. [GitHub apex domain setup](https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site/managing-a-custom-domain-for-your-github-pages-site)
3. GitHub Pages supports one apex domain per site. In the Cloudflare zone for `textwarden.app`, create a **Proxied** A record for `@` pointing to `192.0.2.1` and confirm the edge certificate is active. Create a **Single Redirect** matching `http.host eq "textwarden.app"`. Use the dynamic destination `concat("https://textwarden.io", http.request.uri.path)`, status **301**, and enable **Preserve query string**. [Cloudflare domain redirects](https://developers.cloudflare.com/fundamentals/manage-domains/redirect-domain/)
4. Verify `curl -I https://textwarden.io/` returns 200 and `curl -I 'https://textwarden.app/?ref=local'` returns 301 with `Location: https://textwarden.io/?ref=local`. Check that the Mac download button opens the latest GitHub release.
