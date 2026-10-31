# Choose and refresh models

Open a provider's setup form and choose **Fetch models**, then search the returned
list. Search accepts multiple words in any order. **Type model ID** stays
available when the endpoint has no catalog or its key cannot list models.

Copy one exact ID from your provider's documentation. IDs are case-sensitive;
UAI trims surrounding whitespace, requires valid UTF-8, and accepts at most 160
bytes without control characters or embedded line breaks. Selecting an existing
ID updates the selection without creating another saved entry.

In **Choose a model > Options**, add the selected model to favorites. Favorites
appear first, followed by recently selected models; both lists belong to that
saved provider. UAI keeps up to 100 favorites and the 12 most recent model IDs
per provider. Removing a provider removes its shortcuts. These preferences can
travel with a credential-free configuration export.

Search accepts words in any order, quoted phrases and `-excluded` terms.
Options also offers **Favorites only**, **Known tool support only** and
**Clear model filters**. The tool filter includes only documented support;
clearing it restores models whose capabilities are unknown. Filtering and
favoriting never send inference or change the active model.

Your saved models and discovered models are separate. Fetching a catalog does
not replace the saved model, delete manually entered IDs or establish that the
account can call every listed model. A successful empty refresh clears the
previous discovered list and allows an immediate retry.

Catalogs are cached for ten minutes against connection and authentication
settings. Changing the endpoint, key policy or auth headers invalidates their
use. Closing or changing a setup form makes an older fetch obsolete. Manual
entry can supersede a slow fetch without being replaced when it finishes.

Discovery bounds a catalog to 10,000 entries. Native Gemini discovery also
limits pagination to ten pages. The result explains truncation, invalid IDs and
explicitly incompatible catalog kinds; additional valid IDs can still be entered
manually. Untyped catalog entries do not prove tool, vision or reasoning support.

| Result | Next action |
| --- | --- |
| No `/models` route | Enter the documented exact model or deployment ID |
| Key rejected | Check the key and chosen authentication header |
| Key cannot list models | Enter an authorized ID manually or check account permissions |
| Connection changed | Fetch again for the current connection |

[Troubleshooting](troubleshooting.md) · [All provider guides](README.md)
