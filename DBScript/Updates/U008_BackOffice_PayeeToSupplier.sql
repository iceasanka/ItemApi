/* =============================================================================
   U008_BackOffice_PayeeToSupplier.sql   (2026-10-15)
   Run on: back office db (easyway). SQL Server 2008 R2 and newer. Safe to run again.
   Needs: U007 (z_tb_Supplier.PayeeName, z_tb_WrittenCheque.SuppId / PayeeName).
   Running this file only creates the procedure - no data is changed until you EXEC it.

   Moves the payee list (z_tb_Payee) into the suppliers (z_tb_Supplier), StockSystem.md section 6.19.
   z_tb_Payee is only read, never changed.

   Run a dry run first - it does the whole move inside a transaction, reports, and rolls it back:
       EXEC dbo.z_sp_TransferPayeesToSuppliers @DryRun = 1;
       EXEC dbo.z_sp_TransferPayeesToSuppliers @DryRun = 0;          -- the real one
   Result sets: 1) summary counts, 2) every payee and what was done with it.

   Per supplier name in z_tb_Payee (SupplierName; when empty, PayeeName), trimmed:
     - a supplier with that name exists -> nothing new; its PayeeName is set when still empty (as U007 does)
     - no supplier with that name       -> a NEW supplier:
         SuppCode   = the first @PrefixLen letters (A-Z) of the name in capitals + a 3 digit number not used yet:
                      "Ceylon Biscuits Ltd" -> CEYL001, "Sup1" -> SUP001 (or SUP002 ... when taken).
                      A name with no letters A-Z -> SUPP001.
         SuppName   = the supplier name                (varchar: letters outside the code page become "?", listed)
         PayeeName  = the payee name (active payee first, then the oldest)
         Phone / AccNo / Bank = PhoneNumber / AccountNumber / BankName of that payee (cut to the column size, listed;
                      empty, never NULL - every run also turns NULLs in these supplier columns into empty)
         Status     = 1 when one of its payees is active, else 0
         CreditDays = empty (set the cheque period on the Supplier page), DRate 0
       Email has no column on the supplier and is not copied.
     - two payee names for one supplier: the supplier keeps one (listed - change it on the Supplier page if wrong)
   Old written cheques (z_tb_WrittenCheque) with no supplier get SuppId by the payee's supplier name (else the name
   on the cheque), and PayeeName from the payee. They are NOT added to the supplier ledger (they were paid before it).
   ============================================================================= */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO
IF OBJECT_ID(N'dbo.z_tb_Supplier', 'U') IS NULL OR OBJECT_ID(N'dbo.z_tb_Payee', 'U') IS NULL
   OR OBJECT_ID(N'dbo.z_tb_WrittenCheque', 'U') IS NULL
BEGIN
    RAISERROR('This is not the back office database (z_tb_Supplier / z_tb_Payee / z_tb_WrittenCheque not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
ELSE IF COL_LENGTH('dbo.z_tb_Supplier', 'PayeeName') IS NULL OR COL_LENGTH('dbo.z_tb_WrittenCheque', 'SuppId') IS NULL
BEGIN
    RAISERROR('Run U007_BackOffice_SupplierPayments.sql first (z_tb_Supplier.PayeeName / z_tb_WrittenCheque.SuppId not found) - nothing was changed.', 16, 1);
    SET NOEXEC ON;
END
GO
IF OBJECT_ID(N'dbo.z_sp_TransferPayeesToSuppliers', 'P') IS NOT NULL DROP PROCEDURE dbo.z_sp_TransferPayeesToSuppliers;
GO
CREATE PROCEDURE dbo.z_sp_TransferPayeesToSuppliers
    @DryRun     BIT         = 1,
    @PrefixLen  INT         = 4,      -- letters of the name in the new SuppCode (1 - 6)
    @UserId     VARCHAR(15) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2, @Added INT, @PayeeSet INT, @ChqSupp INT, @ChqPayee INT, @ChqLeft INT, @NullsMended INT;
    SET @Now = SYSDATETIME();
    SET @NullsMended = 0;
    SET @Added = 0; SET @PayeeSet = 0; SET @ChqSupp = 0; SET @ChqPayee = 0;
    IF @PrefixLen IS NULL OR @PrefixLen < 1 SET @PrefixLen = 1;
    IF @PrefixLen > 6 SET @PrefixLen = 6;

    -- 1. the payees, with the supplier name they belong to
    CREATE TABLE #pay (
        PayeeId INT PRIMARY KEY, PayeeName NVARCHAR(200) NOT NULL, SuppName NVARCHAR(200) NOT NULL, IsActive BIT NOT NULL,
        Bank NVARCHAR(150) NULL, AccNo NVARCHAR(50) NULL, Phone NVARCHAR(50) NULL,
        SuppId INT NULL, Action VARCHAR(30) NULL, Note NVARCHAR(400) NULL
    );
    INSERT #pay (PayeeId, PayeeName, SuppName, IsActive, Bank, AccNo, Phone)
    SELECT p.PayeeId, LTRIM(RTRIM(p.PayeeName)),
           CASE WHEN LTRIM(RTRIM(ISNULL(p.SupplierName, N''))) = N'' THEN LTRIM(RTRIM(p.PayeeName))
                ELSE LTRIM(RTRIM(p.SupplierName)) END,
           p.IsActive, NULLIF(LTRIM(RTRIM(p.BankName)), N''), NULLIF(LTRIM(RTRIM(p.AccountNumber)), N''),
           NULLIF(LTRIM(RTRIM(p.PhoneNumber)), N'')
    FROM dbo.z_tb_Payee p;

    UPDATE #pay SET Action = 'skipped', Note = N'No payee or supplier name' WHERE SuppName = N'';

    UPDATE p SET SuppId = s.SuppId, Action = 'existing supplier'
    FROM #pay p
    CROSS APPLY (SELECT TOP 1 x.SuppId FROM dbo.z_tb_Supplier x
                 WHERE LTRIM(RTRIM(x.SuppName)) = p.SuppName ORDER BY x.Status DESC, x.SuppId) s
    WHERE p.Action IS NULL;

    -- 2. one new supplier per name that has none
    CREATE TABLE #new (
        RowId INT IDENTITY(1,1) PRIMARY KEY, SuppName NVARCHAR(200) NOT NULL, PayeeId INT NULL, PayeeName NVARCHAR(200) NULL,
        Status INT NOT NULL, Phone NVARCHAR(50) NULL, AccNo NVARCHAR(50) NULL, Bank NVARCHAR(150) NULL,
        SuppCode VARCHAR(10) NULL, SuppId INT NULL
    );
    INSERT #new (SuppName, Status)
    SELECT SuppName, MAX(CAST(IsActive AS INT))
    FROM #pay WHERE Action IS NULL
    GROUP BY SuppName
    ORDER BY MIN(PayeeId);

    -- its payee: the active one first, then the oldest
    UPDATE n SET PayeeId = p.PayeeId, PayeeName = p.PayeeName, Phone = p.Phone, AccNo = p.AccNo, Bank = p.Bank
    FROM #new n
    CROSS APPLY (SELECT TOP 1 x.PayeeId, x.PayeeName, x.Phone, x.AccNo, x.Bank FROM #pay x
                 WHERE x.Action IS NULL AND x.SuppName = n.SuppName ORDER BY x.IsActive DESC, x.PayeeId) p;

    -- SuppCode: first letters of the name + 001, 002 ... (not used by any supplier, any case)
    DECLARE @Row INT, @Name NVARCHAR(200), @Prefix VARCHAR(10), @K INT, @Ch INT, @N INT, @Code VARCHAR(10);
    SELECT @Row = MIN(RowId) FROM #new;
    WHILE @Row IS NOT NULL
    BEGIN
        SELECT @Name = UPPER(SuppName) FROM #new WHERE RowId = @Row;
        SET @Prefix = '';
        SET @K = 1;
        WHILE @K <= LEN(@Name) AND LEN(@Prefix) < @PrefixLen
        BEGIN
            SET @Ch = UNICODE(SUBSTRING(@Name, @K, 1));
            IF @Ch BETWEEN 65 AND 90 SET @Prefix = @Prefix + CHAR(@Ch);
            SET @K = @K + 1;
        END
        IF @Prefix = '' SET @Prefix = LEFT('SUPP', @PrefixLen);

        SET @N = 1;
        WHILE 1 = 1
        BEGIN
            SET @Code = @Prefix + CASE WHEN @N < 1000 THEN RIGHT('00' + CAST(@N AS VARCHAR(10)), 3) ELSE CAST(@N AS VARCHAR(10)) END;
            IF NOT EXISTS (SELECT 1 FROM dbo.z_tb_Supplier WHERE UPPER(LTRIM(RTRIM(SuppCode))) = @Code)
               AND NOT EXISTS (SELECT 1 FROM #new WHERE SuppCode = @Code)
                BREAK;
            SET @N = @N + 1;
        END
        UPDATE #new SET SuppCode = @Code WHERE RowId = @Row;
        SELECT @Row = MIN(RowId) FROM #new WHERE RowId > @Row;
    END

    -- what does not fit the supplier columns (listed in result set 2)
    UPDATE p SET Note = ISNULL(p.Note + N'; ', N'') + N'Name has letters the supplier table cannot keep (saved as "'
                        + CAST(CAST(n.SuppName AS VARCHAR(500)) AS NVARCHAR(500)) + N'")'
    FROM #pay p JOIN #new n ON n.PayeeId = p.PayeeId
    WHERE CAST(CAST(n.SuppName AS VARCHAR(500)) AS NVARCHAR(500)) <> n.SuppName;
    UPDATE p SET Note = ISNULL(p.Note + N'; ', N'') + N'Phone / account / bank cut to the column size'
    FROM #pay p JOIN #new n ON n.PayeeId = p.PayeeId
    WHERE LEN(n.Phone) > 15 OR LEN(n.AccNo) > 50 OR LEN(n.Bank) > 50;

    -- worked out before the transaction: a dry run's ROLLBACK also undoes changes to the temp tables
    UPDATE p SET Action = CASE WHEN p.PayeeId = n.PayeeId THEN 'new supplier' ELSE 'new supplier (2nd payee)' END
    FROM #pay p JOIN #new n ON n.SuppName = p.SuppName
    WHERE p.Action IS NULL;

    -- a supplier keeps one payee name (the one it has, else its active payee first, then the oldest):
    -- the other payee names of the same supplier are listed
    UPDATE p SET Note = ISNULL(p.Note + N'; ', N'') + N'The supplier''s payee name is "' + k.PayeeName
                        + N'" - this payee name was not copied'
    FROM #pay p
    LEFT JOIN dbo.z_tb_Supplier s ON s.SuppId = p.SuppId
    CROSS APPLY (SELECT ISNULL(s.PayeeName,
                        (SELECT TOP 1 x.PayeeName FROM #pay x
                         WHERE x.SuppName = p.SuppName AND x.Action IS NOT NULL AND x.Action <> 'skipped'
                         ORDER BY x.IsActive DESC, x.PayeeId)) AS PayeeName) k
    WHERE p.Action <> 'skipped' AND k.PayeeName <> p.PayeeName;

    -- 3. save
    BEGIN TRAN;
        INSERT dbo.z_tb_Supplier (SuppCode, SuppName, Status, Phone, Phone2, AccNo, Bank, DRate, UserId, CDate, UDate, PayeeName)
        SELECT SuppCode, CAST(SuppName AS VARCHAR(500)), Status, CAST(ISNULL(LEFT(Phone, 15), N'') AS VARCHAR(15)), '',
               CAST(ISNULL(LEFT(AccNo, 50), N'') AS VARCHAR(50)), CAST(ISNULL(LEFT(Bank, 50), N'') AS VARCHAR(50)), 0,
               ISNULL(@UserId, ''), @Now, @Now, PayeeName
        FROM #new
        ORDER BY RowId;
        SET @Added = @@ROWCOUNT;

        -- empty, not NULL, as the Supplier page saves them (the old ItemApi cannot read a NULL here). Also mends the
        -- suppliers made by the first version of this script.
        UPDATE dbo.z_tb_Supplier SET Phone = ISNULL(Phone, ''), Phone2 = ISNULL(Phone2, ''), AccNo = ISNULL(AccNo, ''),
                                     Bank = ISNULL(Bank, ''), UserId = ISNULL(UserId, '')
        WHERE Phone IS NULL OR Phone2 IS NULL OR AccNo IS NULL OR Bank IS NULL OR UserId IS NULL;
        SET @NullsMended = @@ROWCOUNT;

        -- suppliers that had one already: the payee name when still empty (active payee first, then the oldest)
        UPDATE s SET PayeeName = p.PayeeName, UDate = @Now
        FROM dbo.z_tb_Supplier s
        CROSS APPLY (SELECT TOP 1 x.PayeeName FROM #pay x
                     WHERE x.Action = 'existing supplier' AND x.SuppId = s.SuppId ORDER BY x.IsActive DESC, x.PayeeId) p
        WHERE s.PayeeName IS NULL;
        SET @PayeeSet = @@ROWCOUNT;

        -- old cheques: supplier by the payee's supplier name, else by the name written on the cheque
        UPDATE c SET SuppId = s.SuppId
        FROM dbo.z_tb_WrittenCheque c
        LEFT JOIN #pay p ON p.PayeeId = c.PayeeId
        CROSS APPLY (SELECT TOP 1 x.SuppId FROM dbo.z_tb_Supplier x
                     WHERE LTRIM(RTRIM(x.SuppName)) = ISNULL(p.SuppName, LTRIM(RTRIM(c.SupplierName)))
                     ORDER BY x.Status DESC, x.SuppId) s
        WHERE c.SuppId IS NULL;
        SET @ChqSupp = @@ROWCOUNT;

        UPDATE c SET PayeeName = p.PayeeName
        FROM dbo.z_tb_WrittenCheque c JOIN #pay p ON p.PayeeId = c.PayeeId
        WHERE c.PayeeName IS NULL;
        SET @ChqPayee = @@ROWCOUNT;
        SELECT @ChqLeft = COUNT(*) FROM dbo.z_tb_WrittenCheque WHERE SuppId IS NULL;
    IF @DryRun = 1 ROLLBACK ELSE COMMIT;

    -- the new suppliers' ids (after the COMMIT; a dry run has none)
    IF @DryRun = 0
        UPDATE p SET SuppId = s.SuppId
        FROM #pay p JOIN #new n ON n.SuppName = p.SuppName JOIN dbo.z_tb_Supplier s ON s.SuppCode = n.SuppCode
        WHERE p.SuppId IS NULL;

    -- 4. report
    SELECT CASE WHEN @DryRun = 1 THEN 'DRY RUN - nothing saved' ELSE 'SAVED' END AS Result,
           (SELECT COUNT(*) FROM #pay)                                    AS Payees,
           (SELECT COUNT(DISTINCT SuppName) FROM #pay WHERE SuppName <> N'') AS SupplierNames,
           (SELECT COUNT(*) FROM #pay WHERE Action = 'existing supplier') AS PayeesOfExistingSuppliers,
           @Added                                                         AS SuppliersAdded,
           @NullsMended                                                   AS SuppliersNullsMadeEmpty,
           @PayeeSet                                                      AS ExistingSuppliersGotPayeeName,
           @ChqSupp                                                       AS OldChequesGotSupplier,
           @ChqPayee                                                      AS OldChequesGotPayeeName,
           @ChqLeft                                                       AS ChequesStillWithoutSupplier,
           (SELECT COUNT(*) FROM #pay WHERE Note IS NOT NULL)             AS PayeesWithNote;

    SELECT p.PayeeId, p.PayeeName, p.SuppName AS SupplierName, ISNULL(p.Action, 'skipped') AS Action,
           ISNULL(n.SuppCode, s.SuppCode) AS SuppCode, p.SuppId,
           p.IsActive, p.Note
    FROM #pay p
    LEFT JOIN #new n ON n.SuppName = p.SuppName
    LEFT JOIN dbo.z_tb_Supplier s ON s.SuppId = p.SuppId AND n.RowId IS NULL
    ORDER BY CASE WHEN p.Note IS NOT NULL THEN 0 ELSE 1 END, p.SuppName, p.PayeeId;
END
GO
PRINT 'U008 back office: z_sp_TransferPayeesToSuppliers created. Dry run:  EXEC dbo.z_sp_TransferPayeesToSuppliers @DryRun = 1;';
GO
SET NOEXEC OFF;
GO
