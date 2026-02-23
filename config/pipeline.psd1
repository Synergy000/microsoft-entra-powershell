# Pipeline configuration — edit this file to change shared settings.
# All paths are relative to the repository root.
@{
    # Input CSV files
    GroupsCsv  = 'data/input/groups.csv'
    MembersCsv = 'data/input/members.csv'

    # Bump this value (e.g. v2, v3) to force a fresh PowerShell module install in CI
    ModuleCacheKey = 'v1'
}
