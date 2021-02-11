<?php

defined('TYPO3_MODE') || die('Access denied.');

call_user_func(static function () {
    $GLOBALS['TYPO3_CONF_VARS']['SC_OPTIONS']['t3lib/class.t3lib_tcemain.php']['processDatamapClass']['tx-doktypemapper'] =
        \B13\Doktypemapper\Hooks\DatahandlerHook::class;
});
