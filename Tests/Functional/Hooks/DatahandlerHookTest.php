<?php

declare(strict_types=1);

namespace B13\Doktypemapper\Tests\Functional\Hooks;

/*
 * This file is part of TYPO3 CMS-based extension "doktypemapper" by b13.
 *
 * It is free software; you can redistribute it and/or modify it under
 * the terms of the GNU General Public License, either version 2
 * of the License, or any later version.
 */

use TYPO3\CMS\Core\Database\Connection;
use TYPO3\CMS\Core\Database\ConnectionPool;
use TYPO3\CMS\Core\DataHandling\DataHandler;
use TYPO3\CMS\Core\Localization\LanguageServiceFactory;
use TYPO3\CMS\Core\Utility\GeneralUtility;
use TYPO3\TestingFramework\Core\Functional\FunctionalTestCase;

class DatahandlerHookTest extends FunctionalTestCase
{
    protected array $testExtensionsToLoad = [
        'typo3conf/ext/doktypemapper',
    ];

    /**
     * @test
     */
    public function backendLayoutIsSetForConfiguredDoktype(): void
    {
        $this->importCSVDataSet(__DIR__ . '/Fixtures/Datahandler/backendLayoutIsSetForConfiguredDoktype.csv');
        $this->importCSVDataSet(__DIR__ . '/Fixtures/Datahandler/be_users.csv');
        $backendUser = $this->setUpBackendUser(1);
        $GLOBALS['BE_USER'] = $backendUser;
        $GLOBALS['LANG'] = GeneralUtility::makeInstance(LanguageServiceFactory::class)->createFromUserPreferences($GLOBALS['BE_USER']);
        $dataHandler = GeneralUtility::makeInstance(DataHandler::class);
        $data = [
            'pages' => [
                1 => [
                    'doktype' => 144,
                ],
            ],
        ];
        $dataHandler->start($data, [], $backendUser);
        $dataHandler->process_datamap();
        $queryBuilder = GeneralUtility::makeInstance(ConnectionPool::class)->getQueryBuilderForTable('pages');
        $row = $queryBuilder->select('*')
            ->from('pages')
            ->where(
                $queryBuilder->expr()->eq('uid', $queryBuilder->createNamedParameter(1, Connection::PARAM_INT))
            )
            ->executeQuery()
            ->fetchAssociative();
        self::assertSame('pagets__exampleKey', $row['backend_layout']);
    }
}
