// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

// Smart Contract Programmer Solidity 0.8 TimeLock contract is explained in Turkish by 0xabd_

// TimeLock olayının gerçekleşeceği kontratımız.
// TimeLock: Bir zaman belirliyoruz ve o zaman dolmadan yazdığımız fonksiyonu execute edemiyoruz.
contract TimeLock{
    // Errorların yazılması. Require veya If içerisindeki şartların gerçekleşmediği zamanlar error fırlatmak için kullanıyoruz.
    error NotOwnerError();
    error AlreadyQueuedError(bytes32 txId);
    error TimeStampNotInRangeError(uint blockTimestamp, uint timestamp);
    error NotQueuedError(bytes32 txId);
    error TimestampNotPassedError(uint blockTimestamp, uint timestamp);
    error TimestampExpiredError(uint blockTimestamp, uint timestamp);
    error TxFailedError();


    address public owner; // onlyOwner için
    mapping(bytes32 => bool) public queued; // Transaction'nun sıraya alınıp alınmadığını tutan mapping. Bytes32 çünkü txId kullanıyoruz.

    uint public constant MIN_DELAY = 10; // Minimum beklenilecek süre
    uint public constant MAX_DELAY = 1000; // Maksimum beklenilebilecek süre.
    uint public constant GRACE_TIME = 1000; // Ömür.

    // Sıraya alınma eventi. Transaction bilgileri loglaniyor.
    event Queue( 
        bytes32 indexed txId,
        address indexed target,
        uint value,
        bytes  data,
        string  func,
        uint timestamp
    );

    // Transaction'ın execute edildiginde emitlenecek event. Tx bilgileri loglaniyor.
    event Execute(
        bytes32 indexed txId,
        address indexed target,
        uint value,
        bytes  data,
        string  func,
        uint timestamp
    );
    
    // Transaction'un iptal edileceğinde emitlenecek event.
    event Cancel(bytes32 txId);
    
    // msg.sender'i owner atiyoruz. 
    constructor(){
        owner = msg.sender;
    }
    // Contractimiz ether almasini sağlıyoruz:
    receive() external payable{}
    // Sadece owner tarafından kullanılmayı sağlayan modifier.
    modifier onlyOwner(){
        if (msg.sender != owner){
            revert NotOwnerError();
        }
        _;
    }
    // Transaction bilgilerini kullanarak Bytes32 değişkeninden bir değer döndürüyor. Biz de buna TxId diyoruz.
    function getTxId(
        address _target,
        uint _value,
        bytes calldata _data,
        string calldata _func,
        uint _timestamp
    ) public pure returns(bytes32 txId){
        return keccak256(abi.encode(_target, _value, _data, _func, _timestamp));
    }

    // Sıraya alma fonksiyonu. Sıraya al -> Execute et -> Sıradakini al şeklinde bir işleyimiz var. Yeni fonksiyon çağırmadan önce önündeki fonksiyonun execute edilmesi gerekir.
    function queue(
        address _target,
        uint _value,
        bytes calldata _data,
        string calldata _func,
        uint _timestamp
    ) external onlyOwner { // Transaction bilgilerini parametre olarak alıyoruz.
        bytes32 txId = getTxId(_target, _value, _data, _func, _timestamp); // TxId hesaplaniyor.
        if(queued[txId]){
            revert AlreadyQueuedError(txId); // Zaten sıraya alındıysa hata fırlatıyor.
        }
        if(  // Belirlenecek olan kilit süresinin min delaydan büyük ve max delaydan küçük olması gerekiyor. aksi halde hata fırlatıyor.
            _timestamp < block.timestamp + MIN_DELAY || 
            _timestamp > block.timestamp + MAX_DELAY
        ){
            revert TimeStampNotInRangeError(block.timestamp, _timestamp);
        }

        queued[txId] = true; // Eğer yukarıdaki koşullara takılmadan geçerse sıraya alınıyor ve mapping güncelleniyor.

        emit Queue(txId,_target, _value, _data, _func, _timestamp); // Sıraya alınma eventi emitleniyor.


    }

    function execute(        
        address _target,
        uint _value,
        bytes calldata _data,
        string calldata _func,
        uint _timestamp) external payable onlyOwner returns(bytes memory){ // Tekrardan Tx bilgileri parametre olarak alınıyor. Execute işlemini call ile yapacağımız için return bytes diyoruz.

        bytes32 txId = getTxId(_target, _value, _data, _func, _timestamp); // TxId hesaplaniyor
        if(!queued[txId]){  // Sırada olup olmadığı kontrol ediliyor..
            revert NotQueuedError(txId);
        }
        if(block.timestamp < _timestamp ){ // Execute fonksiyonunun çağrıldığı zamanki zamanın, kilit süresinden küçük olMAMAsı gerekir. (Hala kilitli olur çünkü)
            revert TimestampNotPassedError(block.timestamp, _timestamp);
        }
        if(block.timestamp > _timestamp + GRACE_TIME){ // Execute fonksiyonunun çağrıldığı zamanki zamanın, kilit süresi + GRACE_TIME'dan büyük olmaması gerekir. (Ömrü dolmuş olur.)
            revert TimestampExpiredError(block.timestamp, _timestamp);
        }
        queued[txId] = false; // Sıradan çıkartılıyor. (Execute edilecek çünkü)

        // data'nın oluşturulması. Eğer transaction function selector iceriyorsa, data = function selector ve datanın encode edilmis hali olur. eğer function selector icermiyorsa, data = data olur.
        bytes memory data;
        if(bytes(_func).length > 0){
            data = abi.encodePacked(bytes4(keccak256(bytes(_func))), _data); // bytes4 çünkü func selector ilk 4 byte'da yer alır. Örneğin biz TestTimeLock contractindeki "test()" fonksiyonunu gireceğiz. Bunun keccak256 ile şifrelenmiş halindeki ilk 4 byte function selector görevi görür.
        }
        else{
            data = _data;
        }
        //execute
        (bool ok, bytes memory res) = _target.call{value: _value}(data); // ok = tx gerceklesti/gerceklesmedi, res = response data.
        if(!ok){
            revert TxFailedError();
        }
        emit Execute(txId,_target, _value, _data, _func, _timestamp);
        return res;
    }

    function cancel(bytes32 _txId) external onlyOwner{ // sıradaki tx'i iptal eden fonksiyon
        if(!queued[_txId]){ // sırada olması gerekir.
            revert NotQueuedError(_txId);
        }
        queued[_txId] = false;

        emit Cancel(_txId);
    }


}

contract TestTimeLock{ // contracti test edeceğimiz contract.

    address public timeLock;

    constructor(address _timeLock) { // yukarıda yazdığımız contractin adresini giriyoruz.
        timeLock = _timeLock;
    }

    function test() view external { // test için bu fonksiyonu kullanacağız.
        require(msg.sender == timeLock);
        //more code    
    }

    function getTimestamp() public view returns(uint timestamp){ // çağırdığımız andaki zamanı almamızı sağlayan fonksiyon.
        return block.timestamp + 100; // 100 saniye ilerisini döndürüyor. girdileri yazmamız için bize zaman tanıyor.
    }

}

/* 

TimeLock Nasıl çalışır?

1-) Önce TimeLock kontratını ağa deploy edersiniz. Sonra TimeLock kontrat adresini kullanarak TestTimeLock kontratını deploy edersiniz.
2-) TimeLock kontratında sıraya bir tx koymanız gerekir. Bunun için queue fonksiyonunu kullanırsınız
    _target = TimeLock kontrat adresi
    _value = 0  (ether gondermemize gerek yok.)
    _data = 0x00 
    _func = "test()"
    _timestamp = TestTimeLock kontrati içindeki getTimestamp fonksiyonunu çağırın.
3-) Süre bitince (100 saniye) ayni girdilerle execute fonksiyonunu çağırın. Tebirkler kilit açıldı!


*/