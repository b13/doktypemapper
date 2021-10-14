<?php

declare(strict_types=1);

namespace B13\Doktypemapper\Hooks;

/*
 * This file is part of TYPO3 CMS-based extension "doktypemapper" by b13.
 *
 * It is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, either version 2
 * of the License, or any later version.
 */

use TYPO3\CMS\Backend\Utility\BackendUtility;
use TYPO3\CMS\Core\SingletonInterface;
use TYPO3\CMS\Core\Utility\MathUtility;
use TYPO3\CMS\Core\DataHandling\DataHandler;

class DatahandlerHook implements SingletonInterface
{
    protected $previousBackendLayout;

    /**
     * @param array $fieldArray
     * @param string $table
     * @param mixed $id
     * @param DataHandler $dataHandler
     */
    public function processDatamap_preProcessFieldArray(
        array &$fieldArray,
        string $table,
        $id,
        DataHandler $dataHandler
    ): void {
        if ($table === 'pages') {
            if (!empty($fieldArray['doktype'])) {
                if (MathUtility::canBeInterpretedAsInteger($id)) {
                    $pageTsConfig = BackendUtility::getPagesTSconfig((int)abs((int)$id));
                } elseif (!empty($fieldArray['pid']) && MathUtility::canBeInterpretedAsInteger($fieldArray['pid'])) {
                    $pageTsConfig = BackendUtility::getPagesTSconfig((int)abs((int)$fieldArray['pid']));
                } else {
                    // this can happen with create multiple pages wizard, pid is "-NEW<cnt>"
                    // we can use the previous backend_layout
                    if ($this->previousBackendLayout !== null) {
                        $fieldArray['backend_layout'] = $this->previousBackendLayout;
                    }
                    // this can happen on a new root page
                    return;
                }
                $backendLayouts = (array)$pageTsConfig['mod.']['web_layout.']['BackendLayouts.'];
                foreach ($backendLayouts as $identifier => $data) {
                    if (!empty($data['config.']['backend_layout.']['doktype']) && (int)$data['config.']['backend_layout.']['doktype'] === (int)$fieldArray['doktype']) {
                        $backendLayout = 'pagets__' . str_replace('.', '', $identifier);
                        $fieldArray['backend_layout'] = $backendLayout;
                        $this->previousBackendLayout = $backendLayout;
                        break;
                    }
                }
            }
        }
    }
}
