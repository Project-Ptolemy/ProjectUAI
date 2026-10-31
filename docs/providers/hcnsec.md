# HCNSEC personal accounts

Open **Providers > Add a provider**, search for **HCNSEC**, and select its
**Personal key** card. This preset starts with an empty key and model list.

1. Obtain your personal account's key from HCNSEC.
2. Open **Manage API keys**, add that key and choose **Apply**.
3. Fetch models and choose an exact ID available to your account, or enter an
   ID from your account's documentation.
4. Save the provider. A catalog fetch alone does not verify inference access,
   account balance or tool support.

The preset uses `https://api.hcnsec.cn/v1`, Chat Completions and Bearer
authentication. Your account determines availability, quotas and charges; UAI
does not assume that an HCNSEC model is free or apply the community schedule.

[Project UAI Free](projectuai-free.md) is a separate library choice. Changing a
Free setup draft to HCNSEC removes community keys and the community `auto`
selection. Adding a personal key in that Free draft switches it to HCNSEC and
retains only personal keys. Review the model, then save the connection.

Older personal HCNSEC connections retain their keys, names and model selections
during [migration](migration.md). For multiple keys or pause controls, see
[key management](key-management.md).

[HCNSEC](https://api.hcnsec.cn) · [All provider guides](README.md)
