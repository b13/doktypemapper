# EXT:doktypemapper - A TYPO3 Extension for mapping doktypes to backend_layouts

## Features

By selecting the `doktype` of a page the value of the field ``backend_layout`` is automatically set. There is no need for editors to select a ``backend_layout``. In fact it is recommended to hide the fields ``backend_layout`` and ``backend_layout_next_level`` from editors.

## Installation

Install this extension via `composer req b13/doktypemapper` and activate
the extension in the Extension Manager of your TYPO3 installation.

Once installed, add a new configuration ``doktype`` to your Backend-Layouts.

## Configure your Backend-Layouts

Simply add the new configuration ```doktype``` to your Backend-Layout, e.g.

```
mod.web_layout.BackendLayouts.MyPage.config.backend_layout.doktype = 144
```

This will automatically set the ```backend_layout``` to ``pagets__MyPage`` when a page has doktype ``144``.

### Hide fields from editors

It is recommended to hide the fields ``backend_layout`` and ``backend_layout_next_level`` from page properties (the value is set automatically) using PageTsConfig:

```
TCEFORM.pages.backend_layout.disabled = 1
TCEFORM.pages.backend_layout_next_level.disabled = 1
```

## Credits

This extension was created by Achim Fritz in 2021 for [b13 GmbH, Stuttgart](https://b13.com).

[Find more TYPO3 extensions we have developed](https://b13.com/useful-typo3-extensions-from-b13-to-you) that help us deliver value in client projects. As part of the way we work, we focus on testing and best practices to ensure long-term performance, reliability, and results in all our code.
