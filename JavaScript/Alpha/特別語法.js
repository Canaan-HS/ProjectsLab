// 特殊函數定義
const sum = new Function("a", "b", "return a + b");
console.log(sum(10, 10));

const str = new Function("str", "return str + ' World'");
console.log(str("Hello"));

// 動態綁定
const book = {
    title: "書本標題",
    author: "作者",
    page: 50,
}
with(book) {
    console.log("標題", title);
    console.log("作者", author);
    console.log("頁數", page);
}

// 轉型 (數字)
var number = +"50"
console.log(number + 50);

number = parseInt("50");
console.log(number);

// 轉型規則
console.log("10" + 20 + 30); // 如果是 + 會先判斷開頭的類型, 並將後面的內容進行轉型, 得到 102030
console.log(10 + 20 + "30"); // 反著以數字相加後加上字串 3030
// 如果不是 + 運算, 會嘗試將字串轉為數字, 如果字串非數字, 將會得到 NaN
console.log(10 - "2");
console.log(10 * "2");
console.log(10 / "2");

function HexToRgba(hex, opacity=1) {
    return `rgba(${+("0x"+hex.slice(1, 3))}, ${+("0x"+hex.slice(3, 5))}, ${+("0x"+hex.slice(5, 7))}, ${opacity})`;
}

// 科學記號表示 (1萬, e 代表 10 後面的數字為次方, 所以 1e4 = 1 * 10 ^ 4)
console.log(1e4);

// true, false 簡短表示
console.log(!0);
console.log(!1);

// Array 轉 字串 (a,b,c)
var arr = ["a", "b", "c"];
console.log(arr.toString());

// 字串轉 陣列 (... 語法) [也可用於其他類型數據的轉換]
var a_str = "abcdef"
console.log([...a_str]);

// 合併陣列
var arr2 = ["1", "2", "3"];
console.log([...arr, ...arr2]);

// 字串轉 js
var code = "console.log('這是一個字串');"
eval(code)


// ?. 語法

const box = {
    a: ()=> 1,
}

try {
    box.b();
} catch {
    box?.b?.();
    console.log("?. 語法可以避免, 對空對象做後續處理時, 跳例外");
    // 任何可能會是空對象的, 都可以這樣去寫
    // document.querySelector("main")?.remove();
}

// ?? 語法
var a = "A";
var b = "B";

var p = undefined;

// ?? 當第一個值是 null 或 undefined, 就會取後面的值, 反之就是前面的值 (用 || 能判斷更多類型)
var c = p ?? a;
console.log(c);

// 基本的三元式
var c = p ? a : b;
console.log(c);