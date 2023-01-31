function Generator {
    param (
        [string]$ffmpeg,
        [string]$ffprobe
    )

    return @{
        # 取得緩存路徑名稱 (影片路徑, 放大倍率, 哈希值字元數)
        GetCachePath = {
            param ([string]$path, [int]$scaleFactor, [int]$byte = 20)

            $parent = Split-Path $path
            $name = [System.IO.Path]::GetFileNameWithoutExtension($path)

            $md5 = [System.Security.Cryptography.MD5]::Create()
            $fileBytes = [System.Text.Encoding]::UTF8.GetBytes($name)
            $hashBytes = $md5.ComputeHash($fileBytes)
            $hashString = [BitConverter]::ToString($hashBytes) -replace '-'
            $lowerHash = $hashString.ToLower()

            $fielHash = $lowerHash.Substring(0, [System.Math]::Min($byte, 32))
            return "$parent\$fielHash-x$scaleFactor"
        }

        # 取得最接近的標準解析度 (原始寬度, 原始高度)
        GetResolution = {
            param ([string]$height)

            $height = [int]$height
            $standardHeights = @(144, 240, 360, 480, 576, 720, 1080, 1440, 2160) # 定義標準解析度高度
            $closestHeight = $standardHeights[0]  # 預設為最小值

            foreach ($stdHeight in $standardHeights) {
                if ($stdHeight -le $height) {
                    $closestHeight = $stdHeight  # 更新為當前符合條件的值
                } else {
                    break  # 一旦超過輸入高度，停止循環
                }
            }

            return $closestHeight
        }

        # 取得縮放後大小 (原始寬度, 原始高度, 縮放比)
        GetScaled = {
            param ([string]$width, [string]$height, [int]$scaleFactor)

            # 計算新的解析度
            $newWidth = [math]::Round([int]$width * $scaleFactor)
            $newHeight = [math]::Round([int]$height * $scaleFactor)

            return "$($newWidth):$($newHeight)"
        }

        # 獲取解析後的 指定解析度 (原始寬度, 原始高度, 自定縮放比 字串)
        GetCustomScale = {
            param ([string]$ogWidth, [string]$ogHeight, [string]$scaleString)

            # 使用正則表達式分割
            $parts = $scaleString.Trim() -split "\s*[xX\*\|\s]\s*"

            if ($parts.Count -eq 2) {
                # 嘗試將兩個部分轉換為整數
                $width = $parts[0] -as [int]
                $height = $parts[1] -as [int]

                # 確保兩個部分都是有效的整數
                if ($null -ne $width -and $null -ne $height) {

                    # 計算寬高的縮放比
                    $scaleWidth = $width / [int]$ogWidth
                    $scaleHeight = $height / [int]$ogHeight

                    # 取最大縮放比, 限制範圍 1 ~ 4 倍
                    $scaleFactor = [Math]::Max(1, [Math]::Min(4, [math]::Ceiling([Math]::Max($scaleWidth, $scaleHeight))))

                    # 計算縮小的解析度（如果原解析度 > 目標解析度）
                    $reduceFactor = $null
                    if ($scaleWidth -lt 1 -or $scaleHeight -lt 1) {
                        # 計算縮小的解析度
                        $reduceWidth = [math]::Round($width / $scaleFactor)
                        $reduceHeight = [math]::Round($height / $scaleFactor)

                        # 確保縮放後的解析度符合目標解析度
                        if (($reduceWidth * $scaleFactor) -eq $width -and ($reduceHeight * $scaleFactor) -eq $height) {
                            $reduceFactor = "$([math]::Max(480, $reduceWidth)):$([math]::Max(480, $reduceHeight))"
                        }
                    }

                    # 參數 1: 如果原始影片解析度大於目標解析度，返回縮小後的解析度，否則返回 $null
                    # 參數 2: 縮放乘數 (1~4)
                    # 參數 3: 目標解析度
                    return @($reduceFactor, $scaleFactor, "$($width):$($height)")
                }
            }

            return $null
        }
    }
}