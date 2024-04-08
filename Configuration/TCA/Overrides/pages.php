<?php

defined('TYPO3') or die();

call_user_func(function () {
    $GLOBALS['TCA']['pages']['columns']['backend_layout']['exclude'] = 0;
});
