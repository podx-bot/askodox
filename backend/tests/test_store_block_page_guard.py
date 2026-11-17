"""Owner 2026-11-17: a Meesho link saved as a product named "Access Denied" --
the store's error page was read as the product. Same rule for every store."""
import pytest

from app.services import affiliate_catalog as ac
from app.services import affiliate_providers

BLOCK_PAGES = [
    "<html><head><title>Access Denied</title></head><body>You don't have permission</body></html>",
    "<html><head><title>Just a moment...</title></head></html>",
    "<html><head><title>403 Forbidden</title></head></html>",
    '<html><head><meta property="og:title" content="Attention Required! | Cloudflare"></head></html>',
    "<html><head><title>Robot Check</title></head></html>",
    "<html><head><title>Page Not Found</title></head></html>",
]
URLS = ["https://www.meesho.com/x/p/123", "https://www.amazon.in/dp/B000TEST",
        "https://www.flipkart.com/x/p/itm1", "https://shop.example.in/item/9"]


@pytest.mark.parametrize("html", BLOCK_PAGES)
@pytest.mark.parametrize("url", URLS)
def test_block_page_never_becomes_a_product(url, html):
    result = affiliate_providers.extract(url, fetch=lambda _u: html)
    assert result["status"] == "unavailable" and result.get("blocked") is True
    assert "title" not in result["fields"]


@pytest.mark.parametrize("title", ["Access Denied", "access denied", "Just a moment...", "403 Forbidden",
                                   "Are you a robot?", "Too Many Requests", "404 Not Found"])
def test_block_titles_detected(title):
    assert ac.is_block_page_title(title)


@pytest.mark.parametrize("title", ["Brass glass, Bhog Glass pack of 2", "Error-free digital scale",
                                   "Blocked printing cotton kurti", "Not Found Anywhere Else Saree pack",
                                   "Denim jacket", "Samsung Galaxy M35 5G"])
def test_real_product_names_pass(title):
    assert not ac.is_block_page_title(title)


def test_real_product_page_still_reads():
    html = '<html><head><meta property="og:title" content="Brass pooja glass set"></head></html>'
    result = ac.extract_metadata("https://www.meesho.com/x/p/1", fetch=lambda _u: html)
    assert result["status"] == "ok" and result["fields"]["title"] == "Brass pooja glass set"


def test_saving_or_editing_a_block_title_is_refused(tmp_path):
    store = ac.AffiliateCatalog(str(tmp_path / "c.db"))
    with pytest.raises(ValueError, match="error page"):
        store.create({"title": "Access Denied", "original_product_url": "https://www.meesho.com/x/p/5"}, actor="t")
    item = store.create({"title": "Brass glass", "original_product_url": "https://www.meesho.com/x/p/6"}, actor="t")
    with pytest.raises(ValueError, match="error page"):
        store.update(item["id"], {"title": "Just a moment..."}, actor="t")
