namespace ItemApi.Common
{
    // The business date of a Z = the day it was balanced (its day end). A day end before 06:00 belongs to the day
    // before (a till that sold till after midnight), but never before the day the Z opened. So a Z opened at night
    // right after the last day end and balanced the next night is on the next day, not on the night it opened (U058).
    // Same rule in SQL - till zf_sp_CloseZ:
    //   CASE WHEN CAST(OpenedAt AS DATE) > CAST(DATEADD(HOUR, -6, ClosedAt) AS DATE) THEN CAST(OpenedAt AS DATE)
    //        ELSE CAST(DATEADD(HOUR, -6, ClosedAt) AS DATE) END
    public static class ZDay
    {
        public const int CutoffHour = 6;

        public static DateTime FromDayEnd(DateTime closedAt, DateTime? openedAt = null)
        {
            var day = closedAt.AddHours(-CutoffHour).Date;
            return openedAt is DateTime o && o.Date > day ? o.Date : day;
        }
    }
}
