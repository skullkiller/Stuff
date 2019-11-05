<#
TODO: Search Bar? instead of replacing Title
TODO: Filter thread - reakey host and runspace to filter/update visual - Only for Posh core, windows powershell is too slow rendering
TODO: Multiline Header? - Header is currently capped at first Line - Apply Wrap???
#>
[CmdletBinding(DefaultParameterSetName='NonMultiSel')]
param(
    [Parameter(Mandatory,ValueFromPipeline = $true,Position = 1)]
    [Object[]] $InputObject = @(),
    [Parameter(Position = 2)]
    [String] $Prompt,
    [Parameter(Position = 3)]
    [Object] $DefaultValue,
    [Parameter(Position = 4)]
    [ValidateNotNullorEmpty()]
    [ValidateScript({$_ -gt 0})]
    [Int] $DefaultIndex,
    [Parameter(Mandatory,Position = 5,ParameterSetName='MultiSel')]
    [switch] $MultiSelect,
    [Parameter(Position = 6,ParameterSetName='MultiSel')]
    [ValidateNotNullorEmpty()]
    [ValidateScript({$_ -gt 0})]
    [Int[]] $DefaultSelectedIndex,
    [switch] $MultiLine,
    [object[]] $VisibleItemsFilter,
    [System.Object[]] $Property,
    [System.String[]] $ExcludeProperty,
    [ValidateSet('Double','Single')]
    [string] $dateFormat = 'yyyy-MM-dd',
    [String] $BorderType = 'Double',
    [switch] $indexItems
)

begin {
    Set-StrictMode -Version Latest
    $content = @()
    $errorActionPreference = 'Stop'
    $RawUI = $Host.UI.RawUI
    [Object[]]$Content = @()
    $me = New-Object System.Management.Automation.PSObject -Property @{
        'Colors' = New-Object System.Management.Automation.PSObject -Property @{
            'ContentBack' = 'DarkGray';
            'ContentFore' = 'Yellow';

            'SelectedBack' = 'DarkGreen';
            'SelectedFore' = 'Yellow';

            'BorderBack' = 'DarkBlue';
            'BorderFore' = 'Blue';
            'BorderText' = 'Yellow';

            'HeaderFore' = 'DarkBlue';
            'HeaderBack' = 'Gray';
        };
        'FastScrollItemCount' = 5;
    }

    ##Box Borders Helper
    $BoxChars = New-Object System.Management.Automation.PSObject -Property @{
        'Double' = New-Object System.Management.Automation.PSObject -Property @{
            'Horizontal' = ([char]9552).ToString()
            'Vertical' = ([char]9553).ToString()
            'TopLeft' = ([char]9556).ToString()
            'TopRight' = ([char]9559).ToString()
            'BottomLeft' = ([char]9562).ToString()
            'BottomRight' = ([char]9565).ToString()
        }
        'Single' = New-Object System.Management.Automation.PSObject -Property @{
            'Horizontal' = ([char]9472).ToString()
            'Vertical' = ([char]9474).ToString()
            'TopLeft' = ([char]9484).ToString()
            'TopRight' = ([char]9488).ToString()
            'BottomLeft' = ([char]9492).ToString()
            'BottomRight' = ([char]9496).ToString()
            'Cross' = ([char]9532).ToString()
        }
    }
    $SelectedChars = New-Object System.Management.Automation.PSObject -Property @{
        $False = '→'#safe for older pCS#([char]0x25A2).ToString() #CheckBoxEmpty
        $True = '√'#safe for older pCS#([char]0x2611).ToString() #CheckBoxFilled
    }
    $MultiLineChars = @{
#        'Top' = ([char]0x2B9F).ToString()
        'Top' = ([char]9484).ToString()#([char]0x2193).ToString()
        'Middle' = '│' 
        # 'Bottom' = ([char]0x2B9D).ToString()
        'Bottom' = ([char]9492).ToString() #([char]0x2191).ToString()
        # 'Single' = ([char]0x2B9E).ToString()
        'Single' = '[' #([char]0x2192).ToString()
    }

    <#$otherChars =New-Object System.Management.Automation.PSObject -Property @{
        'CheckBoxEmpty' = ([char]0x25A2).ToString()
        'CheckBoxFilled' = ([char]0x25A0).ToString()
        'CheckBoxGreen' = ([char]0x2611).ToString()
        'XCheckBox' = ([char]0x2327).ToString()
        'GreenCheck' = ([char]8730).ToString()
        'XCheck' = ([char]0x2715).ToString()
        'HeavyXCheck' = ([char]0x2716).ToString()
        'HeavyArrow' = ([char]0x27BD).ToString()
        'LowLine' = ([char]0x005F).ToString()
        'LowDoubleLine' = ([char]0x2017).ToString()
        'VerticalMiddleLine' = ([char]0x007C).ToString()
        'VerticalRightLine' = ([char]0x23B9).ToString()
        'VerticalLeftLine' = ([char]0x23B8).ToString()
        'VerticalMiddleDoubleLine' = ([char]0x2016).ToString()
        'VerticalMiddleTopMArkerLine' = ([char]0x2AEF).ToString()
        'VerticalMiddleBottomMArkerLine' = ([char]0x2AF0).ToString()
        'LineFeedSymbol' = ([char]0x240A).ToString()
    }#>
        
    Function New-Box {
        param(
            [System.Management.Automation.Host.Size] $Size,
            [System.ConsoleColor] $ForegroundColor = $RawUI.ForegroundColor,
            [System.ConsoleColor] $BackgroundColor = $RawUI.BackgroundColor,
            [string] $BorderType = 'Double'
        )

        $LineTop = $BoxChars.$borderType.TopLeft `
                + $BoxChars.$borderType.Horizontal * ($Size.width - 2) `
                + $BoxChars.$borderType.TopRight
        $LineField = $BoxChars.$borderType.Vertical `
                + ' ' * ($Size.width - 2) `
                + $BoxChars.$borderType.Vertical
        $LineBottom = $BoxChars.$borderType.BottomLeft `
                + $BoxChars.$borderType.Horizontal * ($Size.width - 2) `
                + $BoxChars.$borderType.BottomRight

        $Box = & {$LineTop;
                   For ($i=2; $i -lt ($Size.Height) ; $i++){$LineField};
                   $LineBottom
                 }
        ,($RawUI.NewBufferCellArray($Box, $ForegroundColor, $BackgroundColor))
    }

    Function New-Buffer {
        param(
            [System.Management.Automation.Host.Coordinates] $Position,
            [System.Management.Automation.Host.BufferCell[,]] $Buffer
        )

        $BufferBottom = $BufferTop = $Position
        $BufferBottom.X += ($Buffer.GetUpperBound(1))
        $BufferBottom.Y += ($Buffer.GetUpperBound(0))
        $OldBuffer = $RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $BufferTop, $BufferBottom))
        $RawUI.SetBufferContents($BufferTop, $Buffer)
        $Handle = New-Object System.Management.Automation.PSObject -Property @{
            'Content' = $Buffer
            'OldContent' = $OldBuffer
            'Location' = $BufferTop
        }

        Add-Member -InputObject $Handle -MemberType 'ScriptMethod' -Name 'Clear' -Value {$RawUI.SetBufferContents($This.Location, $This.OldContent)}

        $Handle
    }

    Function ConvertTo-BufferCellArray {
        param(
            [String[]] $Content,
            [System.ConsoleColor] $ForegroundColor = $RawUI.ForegroundColor,
            [System.ConsoleColor] $BackgroundColor = $RawUI.BackgroundColor
        )

        ,$RawUI.NewBufferCellArray($Content, $ForegroundColor, $BackgroundColor)
    }

    function WordWrap(){
        param([string] $text,
              [int] $width = [Math]::Max($RawUI.BufferSize.Width,$RawUI.WindowSize.Width) - 1
             )

        function BreakLine(){
            param( [string] $text,
                   [int] $pos,
                   [int] $max
                 )
            ## Find last whitespace in line
            $i = $max;
            while (($i -ge 0) -and (-not [Char]::IsWhiteSpace($text[$pos + $i])) ){$i-=1}
            ## If no whitespace found, break at maximum length
            if ($i -lt 0){return $max}
            ## Find start of whitespace
            while ($i -ge 0 -and [Char]::IsWhiteSpace($text[$pos + $i])){$i--}
            ## Return length of text before whitespace
            return $i + 1;
        }
        $sb = new-object System.Text.StringBuilder;

        ## Lucidity check
        if ($width -lt 1){return $text}

        ## Parse each line of text
        for ($pos = 0; $pos -lt $text.Length; $pos += 1){
            ## Find end of line
            $eol = $text.IndexOf("`n", $pos)
            if ($eol -eq -1){ $eol = $text.Length}

            ## Copy this line of text, breaking into smaller lines as needed
            if ($eol -gt $pos){
                do{
                    $len = $eol - $pos;
                    if ($len -gt $width){$len = BreakLine $text $pos $width};
                    $sb.Append($text, $pos, $len)|out-null;
                    $sb.Append("`n")|out-null;
                    ## Trim whitespace following break
                    $pos += $len;
                    while (($pos -lt $eol) -and [Char]::IsWhiteSpace($text[$pos])){$pos++;}
                }
                while ($eol -gt $pos)
            }else {
                $sb.Append("`n")|out-null ## Empty line
            }
        }
        return $sb.ToString();
    }

    Function Get-WindowSize {
        param(
            [System.Management.Automation.Host.Size] $Size,
            [int] $TitleHeight
        )

        $WindowPosition  = $RawUI.WindowPosition
        $WindowSize = $RawUI.WindowSize
        $Cursor = $RawUI.CursorPosition
        $Center = [Math]::Truncate([Float]$WindowSize.Height / 2)
        $CursorOffset = $Cursor.Y - $WindowPosition.Y
        $CursorOffsetBottom = $WindowSize.Height - $CursorOffset

        # Vertical Placement and size
        $ListHeight = $Size.Height + $titleHeight + 1 <#Status Height#>

        if (($CursorOffset -gt $Center) -and ($ListHeight -ge $CursorOffsetBottom)){
             #$Placement = 'Above'
             $MaxListHeight = $CursorOffset
             if ($MaxListHeight -lt $ListHeight) {$ListHeight = $MaxListHeight}
             $Y = $CursorOffset - $ListHeight + $WindowPosition.Y #- 1
        }else{
            #$Placement =  'Below'
            $MaxListHeight = ($CursorOffsetBottom - 1)
            if ($MaxListHeight -lt $ListHeight) {$ListHeight = $MaxListHeight}
            $Y = $CursorOffSet + 1
        }

        # Horizontal
        $ListWidth = $Size.Width + 4
        if ($ListWidth -gt $WindowSize.Width) {$ListWidth = $Windowsize.Width}
        $Max = $ListWidth
        if (($Cursor.X + $Max) -lt ($WindowSize.Width - 2)) {
            $X = $Cursor.X
        } else {
            if (($Cursor.X - $Max) -gt 0) {
                $X = $Cursor.X - $Max
            } else {
                $X = $windowSize.Width - $Max
            }
        }

        # Output
        New-Object System.Management.Automation.PSObject -Property @{
            #'Orientation' = $Placement;
            'TopX' = $X;
            'TopY' = $Y;
            'ListHeight' = $ListHeight;
            'ListWidth' = $ListWidth;
            'ContentHeight' = $ListHeight - $titleHeight - 1 <#Status Height#>;
        }
    }

    Function New-ConsoleList {
        [CmdletBinding()]
        param(
            [Object[]] $Content,
            [System.ConsoleColor] $BorderForeColor,
            [System.ConsoleColor] $BorderBackColor,
            [System.ConsoleColor] $ContentForeColor,
            [System.ConsoleColor] $ContentBackColor,
            [String] $Title,
            [string] $Header,
            [switch] $MultiSelect,
            [int[]] $DefaultSelectedIndex,
            [int[]] $FilterItems

        )
        

        $ContentWidth = @(([Object[]]$Content|Select-Object -expandproperty text)| Sort-Object Length -Descending)[0].Length
        
        $Header = ($Header -replace "`r`n","`n" -replace "`r","`n" -split "`n")|Select-Object -First 1 ##Keep only First Line of the header
        if(-not [string]::isnullorempty($header)){
            $HeaderHeight = 1
        }else{$HeaderHeight=0}
        $ContentWidth = [Math]::Max($ContentWidth,$Header.Length)
        $MaxWidth = [Math]::Max($RawUI.BufferSize.Width,$RawUI.WindowSize.Width) - 4
        if($MultiSelect.IsPresent){$MaxWidth -= 1}
        if(($content|Measure-Object -Property RowHeight -Maximum).Maximum -gt 1){
            $MultiLine = $true
            $MaxWidth -= 1
            $ContentWidth++
        }else{
            $MultiLine = $false
        }

        #Check for MultiLine Title and get max width of 1st 2 lines - Limited to 2 lines Titles..
        [string[]] $titleArray = ([string[]] $title -replace "`r`n","`n" -replace "`r","`n" -split "`n")|Select-Object -First 2
        $titleWidth = [int]($titleArray|ForEach-Object{$_.length}|Sort-Object -Descending)[0]
        #If single Line and $title > greater box width - Word Wrap
        if ($titleArray.Length -eq 1 -and $titleWidth -gt $MaxWidth - 2){
            $titleArray =  WordWrap $title ($MaxWidth - 2)
            $titleArray = ([string[]] $titleArray -replace "`r`n","`n" -replace "`r","`n" -split "`n")[0,1]
            $titleWidth = [int]($titleArray|ForEach-Object{$_.length}|Sort-Object -Descending)[0]
        }
        $titleHeight = $titleArray.Count
        if($titleWidth -gt $ContentWidth){
            $ContentWidth = $titleWidth + 2
        }
        $StatusWidth = ([string]$content.Count).Length * 4 + 8
        if($StatusWidth -gt $ContentWidth){
            $ContentWidth = $StatusWidth
        }
        $contentHeight = 0
        $i=0
        $contentLines = @()
        if($MultiSelect.IsPresent){
            $SelectedChar = ' '
        }else{
            $SelectedChar = ''
        }
        $Content = foreach ($Item in $Content) {
            $Selected = ($DefaultSelectedIndex -contains ($i + 1))
            if ($MultiSelect.IsPresent){
                $MainSelectedChar = [string] $SelectedChars.$Selected
            }else{
                $MainSelectedChar = ''
            }
            New-Object pscustomobject -property @{
                Selected = $Selected
                Height = $Item.RowHeight
                LinesIndex = @(($contentHeight+1)..($contentHeight + $item.RowHeight))
                Index = $i
            }
            if($MultiLine -eq $true){
                if($item.RowHeight -gt 1){
                    $multiHelper = @($MultiLineChars.Top)
                    for($j=1;$j -lt $Item.RowHeight - 1;$j++){$multiHelper += $MultiLineChars.Middle}
                    $multiHelper += $MultiLineChars.Bottom

                }else{
                    $multiHelper = @($MultiLineChars.Single)
                }
            }else{
                $multiHelper = @((0..($item.RowHeight - 1))|ForEach-Object{''})
            }
            $contentLines += [PSCustomObject] @{ItemIndex=$i;Text= " $($multiHelper[0])$($Item.Text[0])".PadRight($ContentWidth + 2);SText=$MainSelectedChar}
            $contentLines += for($j=1;$j -lt $Item.RowHeight;$j++){
                                [PSCustomObject] @{ItemIndex=$i;Text= " $($multiHelper[$j])$($Item.Text[$j])".PadRight($ContentWidth + 2);SText=$SelectedChar}
                            }
            #>
            $i += 1
            $contentHeight += $item.RowHeight
        }

        

        $Size = New-Object System.Management.Automation.Host.Size $ContentWidth, $contentHeight
        if($MultiSelect.IsPresent){$Size.Width += 1}
        $ListConfig = Get-WindowSize $Size ($titleHeight + $HeaderHeight)
        $BoxSize = New-Object System.Management.Automation.Host.Size $ListConfig.ListWidth, $ListConfig.ListHeight
        $Box = New-Box $BoxSize $BorderForeColor $BorderBackColor
        $Position = New-Object System.Management.Automation.Host.Coordinates ($ListConfig.TopX), $ListConfig.TopY

        $BoxHandle = New-Buffer $Position $Box

        ## Title buffer, shows the Prompt in header of console list (single Line)
        ##"$([char]27)[4m $Prompt $([char]27)[0m" Underlined Title buffer cell???
        #        $title = ($title|Select-Object -first 1|ForEach-Object{$BoxChars.$borderType.Horizontal + " $_ ".padright($ContentWidth,$BoxChars.$borderType.Horizontal)}) -join ''
        $TitleBuffer = ConvertTo-BufferCellArray ($titleArray|ForEach-Object{" $_ "}) $me.Colors.BorderText $me.Colors.BorderBack
        $Position = $Position
        $Position.X += 2
        $null = New-Buffer $Position $TitleBuffer
        $Position.X -= 1
        Remove-Variable 'titleArray' -ea 0
        # place header
        $Position.Y += $titleHeight
        if(-not [string]::isnullorempty($header)){
            $MultilineHelper = 0
            if($MultiLine -eq $true){$SelectedChar += ' ';$MultilineHelper++}
            $HeaderBuffer = ConvertTo-BufferCellArray "$SelectedChar $($Header.PadRight($ContentWidth  - $MultilineHelper)) " $me.Colors.HeaderFore  $me.Colors.HeaderBack
            $null = New-Buffer $Position $HeaderBuffer
        }
        $Position.Y += $HeaderHeight
        
        # Place content
        #<# Visible Items
        if($PSBoundParameters.ContainsKey('FilterItems')){
            $VisibleItemsIndex = @($FilterItems|ForEach-Object{new-object pscustomobject -property ([ordered]@{ItemIndex=$_;LinesIndex=@()})})
        }else{
            $VisibleItemsIndex = @((0..($content.Count - 1))|ForEach-Object{new-object pscustomobject -property ([ordered]@{ItemIndex=$_;LinesIndex=@()})})
        }
        
        $VisibleContentLines = @()
        $VisibleContentLinesIndex = 0
        (0..($VisibleItemsIndex.Count -1))|ForEach-Object{
            $VisibleItemIndex = $_
            $ItemLinesIndex = @()
            $VisibleContentLines += $content[($VisibleItemsIndex[$VisibleItemIndex].ItemIndex)].LinesIndex|ForEach-Object{
                new-object pscustomobject -property @{
                    VisibleItemIndex = $VisibleItemIndex;
                    Line = $contentLines[($_ - 1)]
                }
                $VisibleContentLinesIndex++
                $ItemLinesIndex += $VisibleContentLinesIndex
            }
            $VisibleItemsIndex[$VisibleItemIndex].LinesIndex = $ItemLinesIndex
        }
        $ContentLinesBuffer = @()
        $ContentLinesBufferCount = 0
        $iVItem = 0
        While($ContentLinesBufferCount -lt ($ListConfig.ContentHeight)){
            $Item = $content[$VisibleItemsIndex[$iVItem].ItemIndex]
            $item.LinesIndex|ForEach-Object{
                $ContentLinesBuffer += $contentLines[$_ -1].SText + $contentLines[$_ - 1].Text
                $ContentLinesBufferCount++
                if($ContentLinesBufferCount -ge ($ListConfig.ContentHeight)){break}
            }
            $iVItem++
            if($iVItem -ge $VisibleItemsIndex.Count){
                break
            }
        }
        for($i=$ContentLinesBufferCount;$i -lt $Listconfig.ContentHeight;$i++){
            $contentLinesBuffer += ' ' * ($Size.Width)
        }
        $ContentBuffer = ConvertTo-BufferCellArray $ContentLinesBuffer $ContentForeColor $ContentBackColor
        #>
        #$ContentBuffer = ConvertTo-BufferCellArray (@(0..($ListConfig.ContentHeight-1))|ForEach-Object{$contentLines[$_].SText + $contentLines[$_].Text}) $ContentForeColor $ContentBackColor
        $null<#$ContentHandle#> = New-Buffer $Position $ContentBuffer

        $Position.Y -=1  ###why?????
        $Size.Width += 1
        $LastItem = $visiblecontentLines[$ContentLinesBufferCount - 1].VisibleItemIndex
        if($VisibleItemsIndex[$LastItem].LinesIndex[-1<#LastElement#>] -ne $ContentLinesBufferCount){$LastItem--}
        
        $Handle = New-Object PSCustomObject -Property @{
            'Position' = (New-Object System.Management.Automation.Host.Coordinates $ListConfig.TopX, $ListConfig.TopY)
            'BoxHandle' = $BoxHandle
            'ContentBoxPosition' = $Position
            'ContentBoxHeight' = $Listconfig.ContentHeight
            'ContentBoxWidth' = $Size.Width
            'GuiSelectedItem' = 0
            'Items' = $Content
            'ContentLines' = $contentLines
            'FirstItem' = 0
            'LastItem' = $LastItem
            'FirstLine' = 1
            'LastLine' = $ContentLinesBufferCount
            'VisibleItemsIndex' = $VisibleItemsIndex
            'VisibleContentLines' = $VisibleContentLines
        }
        ## Status buffer, shows at footer of console list.  Displays selected item index, index range of currently visible items, and total item count.
        $StatusBuffer = ConvertTo-BufferCellArray "[$($Handle.GuiSelectedItem + 1)] $($Handle.FirstItem + 1)-$($Handle.LastItem + 1) [$($handle.VisibleItemsIndex.Count)$(if($Handle.VisibleItemsIndex.Count -ne $Handle.Items.count){' *'})]" $me.Colors.BorderText $me.Colors.BorderBack
        $StatusPosition = $Handle.Position
        $StatusPosition.X += 2
        $StatusPosition.Y += ($ListConfig.ListHeight - 1)
        Add-Member -InputObject $Handle -MemberType 'NoteProperty' -Name 'StatusHandle' -Value (New-Buffer $StatusPosition $StatusBuffer)

        $Handle

    }

    Function Move-List {
        param(
            [Int] $X,
            [Int] $Y,
            [Int] $Width,
            [Int] $Height,
            [Int] $Offset
        )

        $Position = $ListHandle.ContentBoxPosition
        $Position.X += $X
        $Position.Y += $Y
        $Rectangle = New-Object System.Management.Automation.Host.Rectangle $Position.X, $Position.Y, ($Position.X + $Width), ($Position.Y + $Height - 1)
        $Position.Y += $OffSet
        $BufferCell = New-Object System.Management.Automation.Host.BufferCell
        $BufferCell.BackgroundColor = $me.Colors.ContentBack
        $RawUI.ScrollBufferContents($Rectangle, $Position, $Rectangle, $BufferCell)
    }


    Function Set-Selection {
        param(
            [Int] $X,
            [Int] $Y,
            [Int] $Width,
            [int] $Height = 1,
            [System.ConsoleColor] $ForegroundColor,
            [System.ConsoleColor] $BackgroundColor
        )
        $Position = $ListHandle.ContentBoxPosition
        $Position.X += $X
        $Position.Y += $Y
        $Y = $Position.Y
        $LineBufferString = @()
        for([int] $i=1;$i -le $Height;$i++){
            $LineBuffer = $RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $Position.X, $Y, ($Position.X + $Width), $Y))
            $LineBufferString += [String]::Join('', ($LineBuffer | ForEach-Object {$_.Character}))
            $Y++
        }
        $LineBuffer = $RawUI.NewBufferCellArray($LineBufferString,$ForegroundColor, $BackgroundColor)
        $RawUI.SetBufferContents($Position, $LineBuffer)
            
    }

    Function Invoke-RedrawContent(){
        $LinePosition = $ListHandle.ContentBoxPosition
        $LinePosition.Y += 1
        if($ListHandle.VisibleItemsIndex.Count -gt 0){
            $LineBuffer = ConvertTo-BufferCellArray ((($ListHandle.FirstLine)..($ListHandle.LastLine))|ForEach-Object{$Line = $ListHandle.VisibleContentLines[$_-1].Line;$Line.SText + $Line.Text}) $me.Colors.ContentFore $me.Colors.ContentBack
            $null = New-Buffer $LinePosition $LineBuffer
            $Y = ($ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].LinesIndex[0] - $ListHandle.FirstLine + 1)
            Set-Selection -X 0 -Y $y -height $ListHandle.Items[$ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex].Height -Width $ListHandle.ContentBoxWidth -Fore $me.Colors.SelectedFore  -Back $me.Colors.SelectedBack
        }
        if(($ListHandle.LastLine - $ListHandle.FirstLine + 1) -lt $ListHandle.ContentBoxHeight){
            $LinePosition.Y += $ListHandle.LastLine - $ListHandle.FirstLine + 1
            $LineBuffer = ConvertTo-BufferCellArray ((($ListHandle.LastLine - $ListHandle.FirstLine + 1)..($ListHandle.ContentBoxHeight-1))|ForEach-Object{' ' * ($ListHandle.ContentBoxWidth+1)}) $me.Colors.ContentFore $me.Colors.ContentBack
            $null = New-Buffer $LinePosition $LineBuffer
        }
        Invoke-RedrawStatusBar
    }

    Function Reset-VisibleContentLines(){
        param([int]$SelectedItemIndex)
        if($ListHandle.VisibleItemsIndex.Count -gt 0){
            $ListHandle.VisibleContentLines = @()
            $VisibleContentLinesIndex = 0
            (0..($ListHandle.VisibleItemsIndex.Count -1))|ForEach-Object{
                $VisibleItemIndex = $_
                $ItemLinesIndex = @()
                $ListHandle.VisibleContentLines += $ListHandle.Items[($ListHandle.VisibleItemsIndex[$VisibleItemIndex].ItemIndex)].LinesIndex|ForEach-Object{
                    new-object pscustomobject -property @{
                        VisibleItemIndex = $VisibleItemIndex;
                        Line = $ListHandle.contentLines[($_ - 1)]
                    }
                    $VisibleContentLinesIndex++
                    $ItemLinesIndex += $VisibleContentLinesIndex
                }
                $ListHandle.VisibleItemsIndex[$VisibleItemIndex].LinesIndex = $ItemLinesIndex
            }
            $ListHandle.LastLine = [math]::Min($ListHandle.ContentBoxHeight,($ListHandle.Items[($ListHandle.VisibleItemsIndex|ForEach-Object{$_.ItemIndex})]|Measure-Object -Property Height -Sum).Sum)
            $ListHandle.FirstLine = 1
            $ListHandle.LastItem = $ListHandle.VisibleContentLines[$ListHandle.LastLine - 1].VisibleItemIndex
            if($ListHandle.VisibleItemsIndex[$ListHandle.LastItem].LinesIndex[-1<#LastElement#>] -ne $ListHandle.LastLine){$ListHandle.LastItem--}
            $ListHandle.GuiSelectedItem = 0
            $SelectedItemIndex = $ListHandle.VisibleItemsIndex|Where-Object{$_.ItemIndex -eq $SelectedItemIndex}|select-object -expand ItemIndex
            $ListHandle.FirstItem = 0
            If($SelectedItemIndex -eq 0 -or $null -eq $SelectedItemIndex){
                Invoke-RedrawContent
            }else{

                Move-Selection $SelectedItemIndex -force -Redraw
            }
        }else{
            $ListHandle.GuiSelectedItem = -1
            $ListHandle.FirstLine = 0
            $ListHandle.FirstItem = -1
            $ListHandle.LastItem = -1
            $ListHandle.LastLine = -1
            Invoke-RedrawContent
        }
    }
    Function Invoke-RedrawStatusBar(){
        ## redraw status buffer
        $ListHandle.StatusHandle.Clear()
        $StatusBuffer = ConvertTo-BufferCellArray "[$($ListHandle.GuiSelectedItem + 1)] $($ListHandle.FirstItem + 1)-$($ListHandle.LastItem + 1) [$($ListHandle.VisibleItemsIndex.Length)$(if($ListHandle.VisibleItemsIndex.Count -ne $ListHandle.Items.count){' *'})]" $me.Colors.BorderText $me.Colors.BorderBack
        $ListHandle.StatusHandle = New-Buffer $ListHandle.StatusHandle.Location $StatusBuffer
    }
    Function Invoke-FilterMenu(){
        $OriginalCursorPosition = $rawui.CursorPosition
        $OriginalForeColor = $rawui.ForegroundColor
        $OriginalBackColor = $rawui.BackgroundColor
        $FilterPosition = $ListHandle.Position
        $OldBuffer = $RawUI.GetBufferContents((New-Object System.Management.Automation.Host.Rectangle $FilterPosition.X, $FilterPosition.y, ($FilterPosition.X+$ListHandle.ContentBoxWidth+2),$FilterPosition.Y))
        $FilterPosition.x+=3
        $LineBuffer = ConvertTo-BufferCellArray @('_' * ($ListHandle.ContentBoxWidth-2)) $me.Colors.BorderText $me.Colors.BorderBack
        $null <#$LineHandle#> = New-Buffer $FilterPosition $LineBuffer
        remove-variable LineBuffer -ea 0
        $rawui.CursorPosition = $filterposition
        $rawui.ForegroundColor = $me.Colors.BorderText
        $rawui.BackgroundColor = $me.Colors.BorderBack
        $FilterString = Read-host -prompt 'Filter'
        $rawui.CursorPosition = $OriginalCursorPosition#restore cursor position
        $rawui.ForegroundColor = $OriginalForeColor
        $rawui.BackgroundColor = $OriginalBackColor
        $RawUI.SetBufferContents($ListHandle.Position, $OldBuffer)
        if(-not [string]::IsNullOrEmpty($FilterString)){
            $FilteredItems = @()
            $FilterString = '(?m)(?=.*' + ([regex]::Escape($filterString) -split '\\ ' -join ')(?=.*') + ')'
            for($i=0;$i -lt ($Content.Count);$i++){
                if(($Content[$i].Text -join "\n") -match $FilterString){
                    $FilteredItems += @(new-object pscustomobject -property ([ordered]@{ItemIndex=$i;LinesIndex=@()}))
                }
            }
            if($ListHandle.VisibleItemsIndex.Count -gt 0){
                $SelectItemIndex = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex
            }else{$SelectItemIndex = 0}
            $ListHandle.VisibleItemsIndex = $FilteredItems
            Reset-VisibleContentLines -SelectedItemIndex $SelectItemIndex
        }
    }

    Function Move-Selection {
        param(
            [Int] $Count,
            [switch] $force,
            [switch] $Redraw
        )
        if($ListHandle.VisibleItemsIndex.Count -eq 0){return}

        $GuiSelectedItem = $ListHandle.GuiSelectedItem
        $FirstItem = $ListHandle.FirstItem
        $LastItem = $ListHandle.LastItem
        if ($Count -ge 0) { ## Down in list
            if ($GuiSelectedItem -eq ($ListHandle.VisibleItemsIndex.Count - 1)) {return}
            $One = 1
            if (    $GuiSelectedItem -eq $LastItem `
                -or (($GuiSelectedItem + $count) -gt $LastItem -and $force.IsPresent)`
               ) {
                $Move = $true
                $Count =[math]::min($count,  $ListHandle.VisibleItemsIndex.Count - $GuiSelectedItem - 1)
            } else {
                $Move = $false
                $Count = [math]::min($count, $LastItem - $GuiSelectedItem)
            }
        } else {#up in the list
            if ($GuiSelectedItem -eq 0) {return}
            $One = -1
            if (    $GuiSelectedItem -eq $FirstItem `
                -or (($GuiSelectedItem + $count) -lt $FirstItem -and $force.IsPresent) `
               ) {#(Move if $Force and item not visibile) or Selecteditem if last full item visible
                $Move = $true
                $Count = - [math]::min($GuiSelectedItem,-$Count)
            }else{
                $Move = $false
                $Count = -[Math]::min($GuiSelectedItem - $FirstItem,-$count)
            }
        }
        $InitialLine = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].LinesIndex[0] - $ListHandle.FirstLine + 1
        $LineCount = 0
        if ($Move) {
            $GuiSelectedItem += $Count
            $FirstItem += $Count
            $LastItem += $Count
            if($LastItem -gt $ListHandle.VisibleItemsIndex.Count - 1){
                $FirstItem -= $LastItem - $ListHandle.VisibleItemsIndex.Count + 1
                if(-not $force.IsPresent){
                    $GuiSelectedItem -= $LastItem - $ListHandle.VisibleItemsIndex.Count + 1
                    $Count -= $LastItem - $ListHandle.VisibleItemsIndex.Count + 1
                }
                $LastItem = $ListHandle.VisibleItemsIndex.Count - 1
            }
            if($FirstItem -lt 0){
                $LastItem -= $FirstItem
                $Count -= $FirstItem
                $FirstItem = 0
            }
            if(-not $force.IsPresent){
                #NOTE:Limit movement to 1 page at a time (based on Original Line Count)
                if($one -eq 1){
                    $LineCount = ($ListHandle.Items[($ListHandle.VisibleItemsIndex[($ListHandle.LastItem+1)..($LastItem)]|ForEach-Object{$_.ItemIndex})]|Measure-Object -Property Height -Sum).Sum
                    $Limit = $ListHandle.LastLine - $ListHandle.VisibleItemsIndex[$ListHandle.LastItem].LinesIndex[-1]
                }else{
                    $LineCount = - ($ListHandle.Items[($ListHandle.VisibleItemsIndex[($FirstItem)..($ListHandle.FirstItem-1)]|ForEach-Object{$_.ItemIndex})]|Measure-Object -Property Height -Sum).Sum
                    $Limit = $ListHandle.VisibleItemsIndex[$ListHandle.FirstItem].LinesIndex[0] - $ListHandle.FirstLine
                }
                $LineCount -= $Limit * $one
                $Limit += $ListHandle.Items[$ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex].Height
                $limit = $ListHandle.ContentBoxHeight - $Limit
                while([math]::abs($linecount) -gt $limit){
                    if($one -eq 1){
                        $LineCount -= $ListHandle.Items[$ListHandle.VisibleItemsIndex[$ListHandle.LastItem + $Count].ItemIndex].Height
                    }else{
                        $LineCount += $ListHandle.Items[$ListHandle.VisibleItemsIndex[$ListHandle.FirstItem + $Count].ItemIndex].Height
                    }
                    $Count -= $one
                }
                $GuiSelectedItem = $ListHandle.GuiSelectedItem + $Count
                $FirstItem = $ListHandle.FirstItem + $Count
                $LastItem = $ListHandle.LastItem + $Count
            }else{
                while($ListHandle.VisibleItemsIndex[$LastItem].LinesIndex[-1] - $ListHandle.VisibleItemsIndex[$FirstItem].LinesIndex[0] -ge $ListHandle.ContentBoxHeight){
                    $LastItem--
                }
            }
            if ($One -eq 1) {
                if($ListHandle.LastItem -eq $LastItem){
                    $LineCount = 0
                }else{
                    $LineCount = ($ListHandle.Items[($ListHandle.LastItem + 1)..($LastItem)]|Measure-Object -Property Height -Sum).Sum
                    $LineCount -= $ListHandle.LastLine - $ListHandle.VisibleItemsIndex[$ListHandle.LastItem].LinesIndex[-1]
                }
            } else {
                if($ListHandle.FirstItem -eq $FirstItem){
                    $Linecount = 0
                }else{
                    $LineCount = - ($ListHandle.Items[($ListHandle.VisibleItemsIndex[($FirstItem)..($ListHandle.FirstItem-1)]|ForEach-Object{$_.ItemIndex})]|Measure-Object -Property Height -Sum).Sum
                    $LineCount += $ListHandle.VisibleItemsIndex[$ListHandle.FirstItem].LinesIndex[0] - $ListHandle.FirstLine
                }
            }
            $ListHandle.FirstLine += $LineCount
            $ListHandle.LastLine += $LineCount
        } else {
            $GuiSelectedItem += $Count
        }
        $ListHandle.FirstItem = $ListHandle.VisibleContentLines[$ListHandle.FirstLine-1].VisibleItemIndex
        if($ListHandle.VisibleItemsIndex[$ListHandle.FirstItem].LinesIndex[0] -lt $ListHandle.FirstLine){$ListHandle.FirstItem++}
        $ListHandle.LastItem = $ListHandle.VisibleContentLines[$ListHandle.LastLine-1].VisibleItemIndex
        if($ListHandle.VisibleItemsIndex[$ListHandle.LastItem].LinesIndex[-1] -gt $ListHandle.LastLine){$ListHandle.LastItem--}

        if(-not $Redraw.IsPresent){
            #unHighlight selected Line
            Set-Selection -X 0 -Y $InitialLine -height $ListHandle.Items[$ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex].Height -Width $ListHandle.ContentBoxWidth -Fore $me.Colors.ContentFore  -Back $me.Colors.ContentBack
        }
        if($Move){
            #Draw "New Items"
            if([Math]::Abs($LineCount) -lt $ListHandle.ContentBoxHeight){
                $h = $ListHandle.LastLine + [Math]::min(0,$ListHandle.ContentBoxHeight + $Linecount)
            }else{$h = $ListHandle.LastLine}
            $array = ([math]::max($ListHandle.VisibleItemsIndex[[math]::min($GuiSelectedItem,$ListHandle.GuiSelectedItem+1)].LinesIndex[0],$ListHandle.FirstLine))..$h
            $LinePosition = $ListHandle.ContentBoxPosition
            if($one -eq 1){
                $LinePosition.Y += [math]::max($ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem+1].LinesIndex[0],$ListHandle.FirstLine) - $ListHandle.FirstLine + 1
            }else{
                $LinePosition.Y += [math]::min($ListHandle.VisibleItemsIndex[$GuiSelectedItem].LinesIndex[0],$ListHandle.FirstLine) - $ListHandle.FirstLine + 1                
            }
            if(-not $Redraw.IsPresent){
                $LineBuffer = ConvertTo-BufferCellArray ($array|ForEach-Object{$Line = $ListHandle.VisibleContentLines[$_-1].Line;$Line.SText + $Line.Text}) $me.Colors.ContentFore $me.Colors.ContentBack
                remove-variable array,h -ea 0 -Force
                #move existing items
                Move-List 0 1 $ListHandle.ContentBoxWidth $ListHandle.ContentBoxHeight (-$LineCount)
                $null <#$LineHandle#> = New-Buffer $LinePosition $LineBuffer
                remove-variable LineBuffer,LinePosition -ea 0 -Force
            }
        }
        if(-not $Redraw.IsPresent){
            #Highlight new selected Line
            Set-Selection -X 0 -Y ($ListHandle.VisibleItemsIndex[$GuiSelectedItem].LinesIndex[0]-$ListHandle.FirstLine + 1) -Height $ListHandle.Items[$ListHandle.VisibleItemsIndex[$GuiSelectedItem].ItemIndex].Height -Width $ListHandle.ContentBoxWidth -Fore $me.Colors.SelectedFore -Back $me.Colors.SelectedBack
        }
        $ListHandle.GuiSelectedItem = $GuiSelectedItem
        if(-not $Redraw.IsPresent){
            Invoke-RedrawStatusBar
        }else{
            Invoke-RedrawContent
        }
    }
}

process {
    $content+=$InputObject
}

end {
    ## If contents contains less then minimum options, then forward contents without displaying console list
    #if ($Content.Length -eq 1){$Content;return}#removed as we still have cancel as 2nd option
    if($content.count -eq 0){return}
    $ParseableContent = $content
    if($ParseableContent[0] -is [hashtable] -or $ParseableContent[0] -is [Collections.Specialized.OrderedDictionary]){
        $ParseableContent = $ParseableContent|ForEach-Object{New-Object System.Management.Automation.PSObject -Property $_}
    }
    $header = $null #Strict Mode...
    $TypeName = $ParseableContent[0].gettype().name
    if (('String','Int16','Int32','Int64','Single','UInt16','UInt32','UInt64','Char','Long','Boolean','Decimal','Double','Guid') -contains $TypeName){
        $txtScript = {$ParseableContent[$i]}
    }elseif($TypeName -eq 'DateTime'){
        if ($PSBoundParameters.ContainsKey('DateFormat')){
            $txtScript = {get-date -date $ParseableContent[$i]}
        }else{ $txtScript = {get-date -format $dateFormat -date $ParseableContent[$i]}}
    }else{
        #Limitations: When multiline the "biggest" Column sometimes could be capped so that all cols fit - make biggest column the last when determining the withs?
        $params = @{}
        if($PSBoundParameters.ContainsKey('Property')){ $params.Add('Property',$Property)}
        if($PSBoundParameters.ContainsKey('ExcludeProperty')){ $params.Add('ExcludeProperty',$ExcludeProperty)}
        $format = $ParseableContent|Select-Object @params|Format-Table -AutoSize -Wrap
        Remove-Variable 'params' -ea 0 -force
        $columns = @()
        $RowValues = @()
        #$GroupingValues=@()
        $CurrentGroup = $null
        $Groupingfield = $null
        ForEach($out in $format) {
            switch($out.pstypenames[0]){
                'Microsoft.PowerShell.Commands.Internal.Format.FormatStartData' {
                    # Capture the headers and convert them to one header
                    ForEach($col in $out.shapeinfo.tablecolumninfolist) {
                    if($col.width -gt 0){
                        $fixedWidth = $col.width
                    }else{
                        $fixedwidth = [int] $null
                    }
                    if($null -ne $col.propertyName){
                        $Name = $col.propertyName
                    }else{
                        $Name = $col.label
                    }
                    if($fixedWidth -eq 0){
                        $width = $Name.Length
                    }else{
                        $width = $fixedWidth
                    }
                    $columns += New-Object pscustomobject -property @{'Name'=$Name;'fixedWidth' = $fixedWidth;'Width'=[MAth]::max($Width,$Name.Length)}
                    }
                }
                'Microsoft.PowerShell.Commands.Internal.Format.FormatEntryData' {
                    # Capture the values and convert them to one value
                    $Row=[ordered]@{}
                    $i = 0
                    foreach($col in $out.formatentryinfo.formatPropertyFieldList) {
                        $value = $col.propertyvalue.ToString()
                        $valueLines = [string[]] $value -replace "`r`n","`n" -replace "`r","`n" -split "`n"
                        if ($MultiLine.IsPresent){
                            $Width = [int]($valueLines|ForEach-Object{$_.length}|Sort-Object -Descending)[0]
                        }else{
                            $value = $valueLines[0]
                            $Width = [int]($valueLines|ForEach-Object{$_.length})[0]
                        }# since this is singleline at the moment
                        if($columns[$i].fixedWidth -eq 0 -and $columns[$i].Width -lt $Width){
                            $columns[$i].Width = $width
                        }
                        $Row += @{"$($columns[$i].name)"=$value} #replace with value for MultiLine
                        $i++
                    }
                    if($null -ne $Groupingfield){
                        $Row += @{"$Groupingfield"=$CurrentGroup}
                    }
                    $RowValues += new-object pscustomobject -property $row
                }
                'Microsoft.PowerShell.Commands.Internal.Format.GroupStartData'{
                    $CurrentGroup = $null
                    $Groupingfield = $null
                    if($null -ne $out.groupingEntry){
                        $Groupingfield = $out.groupingEntry.formatValueList[0].formatValueList[0].formatValueList[0].formatValueList[0].text -replace ':\s*$',''
                        $CurrentGroup = $out.groupingEntry.formatValueList[0].formatValueList[0].formatValueList[0].formatValueList[1].propertyValue
                    }
                }
                #default{$null = $out.pstypenames[0]}
            }
        }
        Remove-Variable format -ea 0 -force
        $ExtraSpace = switch($MultiSelect.IsPresent){$true {5;break} default {4;break}}
        $ExtraSpace += switch($MultiLine.IsPresent){$true {1;break} default {0;break}}
        $MaxListWidth = $host.ui.RawUI.WindowSize.Width - $ExtraSpace

        $headerSeparatorFound = $false
        $columns4FT = @(@{name='-';e={'-'};width=1})
        if($indexItems.IsPresent){
            $script:RowIndex=-2
            $columns4FT+= @(@{name=' ';e={$script:rowindex++;$script:RowIndex};width=$content.count.ToString().length})
        }
        $columns4FT += @($columns|ForEach-Object{@{e=$_.name;width=$_.width}})
        $format = @($RowValues|format-table $columns4FT -Wrap:($MultiLine.IsPresent) -GroupBy $Groupingfield| `
                            Out-String -Stream -Width ($MaxListWidth+2)| `
                    Select-Object -skip 1 <#Format Table always adds a extra line on top, at least without the headers#> |`
                    ForEach-Object{
                        if($_ -match '^-[ -]+$'){
                            $headerSeparatorFound = $true
                        }elseif([string]::IsNullOrWhiteSpace($_)){<#don't consider empty lines#>}
                        else{
                            if($headerSeparatorFound){
                                if($null -ne $Groupingfield -and $_ -match '^ +$Groupingfield: (.*)$'){
                                    $CurrentGroup = $matches[1]
                                }else{
                                    [pscustomobject] @{Group=$CurrentGroup;Text=$_}
                                }
                            }
                            else{$header +=  "`n" + ($_.remove(0,2))}
                        }
                    })
        Remove-Variable headerSeparatorFound,RowValues -ea 0
        $header = $header.trim("`n")
        $FormatLine = 0
        for($i=0;$i -lt $content.count;$i++){
            $RowHeight = 0
            $CurrentGroup = $Format[$formatLine].Group
            $Text =  @(. {
                do{
                    $Format[$formatLine].Text.remove(0,2)
                    $formatLine++
                    $rowHeight++      
                    try{if($format[$FormatLine].Text -Like '- *'){break}}catch{}
                }while($formatLine -lt $format.Count)
            })
            $content[$i] = new-object pscustomobject -property ([ordered]@{
                    'Value' = $content[$i];
                    'Text' = $text
                    'RowHeight' = $RowHeight
                    'Group' = $CurrentGroup
                })
        }
        Remove-Variable ParseableContent, format, RowHeights -ea 0

    }
    if ($null -ne (Get-Variable txtScript -ValueOnly -ea 0)){
        for($i=0;$i -lt $content.count;$i++){
                $content[$i] = New-Object pscustomobject -property ([ordered]@{'Value' = $content[$i]; 'Text' = @(,(& $txtScript)); 'RowHeight'=1; 'Group'=$null})
        }
    }
    Remove-Variable ExtraSpace, txtscript -ea 0

    $temp = Get-Member -InputObject $content[0] -Type Properties|Select-Object -ExpandProperty Name
    if ( -not (      ($temp -contains 'Value') `
                -and ($temp -contains 'Text') `
                -and ($temp -contains 'RowHeight') `
                -and ($temp -contains 'Group') `
                -and ($temp.Count -eq 4)
               )
        ){throw 'items not parseable'}

    ## Select the first item in the list
    $GuiSelectedItem = 0
    $params = @{
        'Content' = $Content
        'BorderForeColor' = $me.Colors.BorderFore
        'BorderBackColor' = $me.Colors.BorderBack
        'ContentForeColor' = $me.Colors.ContentFore
        'ContentBackColor' = $me.Colors.ContentBack
        'Title' = $Prompt
        'Header' = $Header
        'MultiSelect' = $MultiSelect
        'DefaultSelectedIndex' = $DefaultSelectedIndex
    }


    if($PSBoundParameters.ContainsKey('VisibleItemsFilter')){
        $VisibleItemsFilteredItemsIndex = @()
        if($VisibleItemsFilter -is [hashtable] -or $VisibleItemsFilter -is [Collections.Specialized.OrderedDictionary]){
            if($content[0].Value -is [hashtable] -or $content[0].Value -is [Collections.Specialized.OrderedDictionary]){
                $compScript = { $match = $true
                                foreach($key in $VisibleItemsFilter.Keys){
                                    $match = $content[$i].Value.ContainsKey($key) -and $content[$i].Value[$key] -like $VisibleItemsFilter[$key]
                                    if(-not $match){break}
                                }
                                $match
                            }
            }else{
                $compScript = { $match = $true
                    foreach($key in $VisibleItemsFilter.Keys){
                        $match = $content[$i].Value.PSobject.Properties.Match($key).Count -gt 0 -and $content[$i].Value.$key -like $VisibleItemsFilter[$key]
                        if(-not $match){break}
                    }
                    $match
                }
            }
        }else{$compscript = {$content[$i].text -like $VisibleItemsFilter}}
        for ($i=0;$i -lt ($content.Count);$i++){
            if((& $compscript)){ $VisibleItemsFilteredItemsIndex+= $i
            }
        }
        Remove-variable 'compscript' -ea 0
        if($VisibleItemsFilteredItemsIndex.Count -gt 0){
            $params.Add('FilterItems',$VisibleItemsFilteredItemsIndex)
        }
    }
    try{
    ## Create console list
    $ListHandle = New-ConsoleList @params
    if($ListHandle.VisibleItemsIndex.Count -eq 1){
        Set-Selection -X 0 -Y 1 -height $ListHandle.Items[$ListHandle.VisibleItemsIndex[0].ItemIndex].Height -Width $ListHandle.ContentBoxWidth -Fore $me.Colors.SelectedFore  -Back $me.Colors.SelectedBack
    }else{
        if($PSBoundParameters.ContainsKey('DefaultValue')){
            if($DefaultValue -is [hashtable] -or $DefaultValue -is [Collections.Specialized.OrderedDictionary]){
                if($content[0].Value -is [hashtable] -or $content[0].Value -is [Collections.Specialized.OrderedDictionary]){
                    $compScript = { $match = $true
                                    foreach($key in $DefaultValue.Keys){
                                        $match = $content[$i].Value.ContainsKey($key) -and $content[$i].Value[$key] -like $DefaultValue[$key]
                                        if(-not $match){break}
                                    }
                                    $match
                                }
                }else{
                    $compScript = { $match = $true
                        foreach($key in $DefaultValue.Keys){
                            $match = $content[$i].Value.PSobject.Properties.Match($key).Count -gt 0 -and $content[$i].Value.$key -like $DefaultValue[$key]
                            if(-not $match){break}
                        }
                        $match
                    }
                }
            }else{$compscript = {$content[$i].text -like $DefaultValue}}
            for ($j=0;$j -lt ($ListHandle.VisibleItemsIndex.Count);$j++){
                $i = $ListHandle.VisibleItemsIndex[$j].ItemIndex
                if((& $compscript)){
                    $GuiSelectedItem = $j
                    break
                }
            }
            Remove-variable 'compscript' -ea 0
        }
        if(      $PSBoundParameters.ContainsKey('DefaultIndex') -and ($content.count -ge $DefaultIndex) `
            -and ($ListHandle.VisibleItemsIndex|select-object -expand ItemIndex) -contains ($DefaultIndex-1)){
            $GuiSelectedItem = ($ListHandle.VisibleItemsIndex|select-object -expand ItemIndex).IndexOf($DefaultIndex - 1)
        }
        #Default selection is 1st item, if default value/index is different, will move selection to the new item
        Move-Selection $GuiSelectedItem -force
    }
    ## Listen for first key press
    $Key = $RawUI.ReadKey('NoEcho,IncludeKeyDown')
    ## Process key presses

    $Continue = $true

    while ($Key.VirtualKeyCode -ne 27 -and $Continue -eq $true) {
        $Shift = $Key.ControlKeyState.ToString()
        switch ($Key.VirtualKeyCode) {
            9 { ## Tab
                if ($Shift -match 'ShiftPressed') {
                    Move-Selection -1  ## Up
                } else {
                    Move-Selection 1  ## Down
                }
                break
            }
            38 { ## Up Arrow
                if ($Shift -match 'ShiftPressed') {
                    ## Fast scroll selected
                    Move-Selection (- $me.FastScrollItemCount)
                } else {
                    Move-Selection -1
                }
                break
            }
            40 { ## Down Arrow
                if ($Shift -match 'ShiftPressed') {
                    ## Fast scroll selected
                    Move-Selection $me.FastScrollItemCount
                } else {
                    Move-Selection 1
                }
                break
            }
            33 { ## Page Up
                Move-Selection (-$ListHandle.ContentBoxHeight + 1)
                break
            }
            34 { ## Page Down
                Move-Selection ($ListHandle.ContentBoxHeight - 1)
                break
            }
            35 { ## End
                Move-Selection ($ListHandle.items.count) -force
                break
            }
            36 { ## Home
                Move-Selection (-$ListHandle.items.count) -force
                break
            }

            32 { ## Space
                if($MultiSelect.IsPresent){
                    $VisibleItem = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem]
                    $ListHandle.Items[$VisibleItem.ItemIndex].Selected = -not $ListHandle.Items[$VisibleItem.ItemIndex].Selected
                    $Item = $ListHandle.Items[$VisibleItem.ItemIndex]
                    $ListHandle.VisibleContentLines[$VisibleItem.LinesIndex[0]-1].Line.SText = $SelectedChars.($Item.Selected)
                    $Line = $ListHandle.VisibleContentLines[$VisibleItem.LinesIndex[0]-1].Line
                    $LineBuffer = ConvertTo-BufferCellArray ($Line.SText + $Line.Text) $me.Colors.SelectedFore $me.Colors.SelectedBack
                    $LinePosition = $ListHandle.ContentBoxPosition
                    $LinePosition.Y += $VisibleItem.LinesIndex[0] - $ListHandle.FirstLine + 1
                    $null <#$LineHandle#> = New-Buffer $LinePosition $LineBuffer
                }
                break
            }

            13 { ## Enter
                ## Expand with currently selected item and Clear the list
                $ListHandle.BoxHandle.Clear()
                if($MultiSelect.IsPresent){
                    $array = $ListHandle.Items|Where-Object{$_.Selected -eq $true}|ForEach-Object{$_.Index}
                    if($null -ne $array){$content[$array]|ForEach-Object{$_.Value}}
                }else{
                    if($ListHandle.VisibleItemsIndex.count -gt 0){
                        $content[$ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex].Value
                    }
                }
                $ListHandle = $null
                $Continue = $false
                break
            }

            113 {##F2
                #Reset Filter only if it's not reset yet
                if($ListHandle.Items.Count -gt $ListHandle.VisibleItemsIndex.Count){
                    if($ListHandle.GuiSelectedItem -ge 0){
                        $newIndex = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex
                    }else{$newIndex = 0}
                    $ListHandle.VisibleItemsIndex = @((0..($ListHandle.Items.Count - 1))|ForEach-Object{new-object pscustomobject -property ([ordered]@{ItemIndex=$_;LinesIndex=@()})})
                    $ListHandle.GuiSelectedItem = $newIndex
                    Reset-VisibleContentLines -SelectedItemIndex $newIndex
                }
            }

            69{#E
                if ($Shift -match 'CtrlPressed') {
                    Invoke-FilterMenu
                }
            }
            65{#A
                if($MultiSelect.IsPresent -and $Shift -match 'CtrlPressed') {
                    $Select = $true
                    (0..($ListHandle.Items.Count - 1))|ForEach-Object{
                        if($true -eq $ListHandle.ITems[$_].Selected){
                            $select = $false;
                            return
                        }
                    }
                    (0..($ListHandle.Items.Count - 1))|ForEach-Object{
                        $ListHandle.ITems[$_].Selected = $select
                        $ListHandle.ContentLines[$ListHandle.Items[$_].LinesIndex[0]-1].SText = $SelectedChars.($select)

                    }
                    (0..($ListHandle.VisibleItemsIndex.Count - 1))|ForEach-Object{
                        $ListHandle.VisibleContentLines[$ListHandle.VisibleItemsIndex[$_].LinesIndex[0]-1].Line.SText = $SelectedChars.($Select)

                    }
                    Invoke-RedrawContent
                }
            }

            82{#R
                if ($Shift -match 'CtrlPressed') {
                    if($ListHandle.GuiSelectedItem -ge 0){
                        $newIndex = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex
                    }else{$newIndex = 0}
                    $ListHandle.VisibleItemsIndex = @((0..($ListHandle.Items.Count - 1))|ForEach-Object{new-object pscustomobject -property ([ordered]@{ItemIndex=$_;LinesIndex=@()})})
                    $ListHandle.GuiSelectedItem = $newIndex
                    Reset-VisibleContentLines -SelectedItemIndex $newIndex
                }
            }
            83{#S
                if($MultiSelect.IsPresent -and $Shift -match 'CtrlPressed') {
                    if($ListHandle.GuiSelectedItem -ge 0){
                        $newIndex = $ListHandle.VisibleItemsIndex[$ListHandle.GuiSelectedItem].ItemIndex
                    }else{$newIndex = 0}
                    $ListHandle.VisibleItemsIndex = @((0..($ListHandle.Items.Count - 1))|where-object{$ListHandle.ITems[$_].Selected}|ForEach-Object{new-object pscustomobject -property ([ordered]@{ItemIndex=$_;LinesIndex=@()})})
                    Reset-VisibleContentLines -SelectedItemIndex $newIndex
                }
            }
            
        }

        ## Listen for next key press
        if ($Continue) {$Key = $RawUI.ReadKey('NoEcho,IncludeKeyDown')}
    }
}catch{ throw $_}
finally{
    if($null -ne (Get-Variable ListHandle -ValueOnly -ea 0)){try{$ListHandle.BoxHandle.Clear()}catch{}}
}

}  ## end of 'end' block
