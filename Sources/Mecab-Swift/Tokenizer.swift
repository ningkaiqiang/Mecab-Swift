import mecab
import Foundation
import StringTools
import Dictionary
import Darwin

/**
A tokenizer /  morphological analyzer for Japanese
*/
public class Tokenizer{
    
    /**
    How to display found tokens in Japanese text
    */
   public enum Transliteration{
        case hiragana
        case katakana
        case romaji
    }

    public enum TokenizerError:Error{
        case initializationFailure(String)
        
        public var localizedDescription: String{
            switch self {
            case .initializationFailure(let error):
                return error
            }
        }
    }
    
    
    private let dictionary:DictionaryProviding
    
    fileprivate let _mecab:OpaquePointer!
    
    /**
     The version of the underlying mecab engine.
     */
    public class var version:String{
        return String(cString: mecab_version(), encoding: .utf8) ?? ""
    }
    
    
    
    fileprivate let isSystemTokenizer:Bool

    #if canImport(CoreFoundation)
    fileprivate init(){
        self.isSystemTokenizer=true
        self.dictionary=SystemDictionary()
        _mecab=nil
    }
    
    
     /*
     The CoreFoundation CFStringTokenizer
     **/
    public static let systemTokenizer:Tokenizer = {
        return Tokenizer()
    }()
    #endif
    
    /**
     Initializes the Tokenizer.
     - parameters:
        - dictionary:  A Dictionary struct that encapsulates the dictionary and its positional information.
     - throws:
        * `TokenizerError`: Typically an error that indicates that the dictionary didn't exist or couldn't be opened.
     */
    public init(dictionary:DictionaryProviding) throws{
        self.dictionary=dictionary
        self.isSystemTokenizer=false
        let tokenizer=try dictionary.url.withUnsafeFileSystemRepresentation({path->OpaquePointer in
            guard let path=path,
                let dictPath=String(cString: path).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
                //MeCab splits the commands by spaces, so we need to escape the path passed inti the function.
                //We replace the percent encoded space when opening the dictionary. This is mostly relevant when the dictionary os located inside a folder of which we cannot control the name, i.e. Application Support
                else{ throw TokenizerError.initializationFailure("URL Conversion Failed \(dictionary)")}
            
            guard let tokenizer=mecab_new2("-d \(dictPath)") else {
                let error=String(cString: mecab_strerror(nil), encoding: .utf8) ?? ""
                throw TokenizerError.initializationFailure("Opening Dictionary Failed \(dictionary) \(error)")
            }
            return tokenizer
        })
        
        _mecab=tokenizer
       
    }
    
    /**
     The fundamental function to tokenize Japanese text with an initialized `Tokenizer`
     - parameters:
        - text: A `string` that contains the text to tokenize.
        - transliteration : A `Transliteration` method. The text content of found tokens will be displayed using this.
     - returns: An array of `Annotation`, a struct that contains the found tokens (the token value, the reading, POS, etc.).
     */
    public func tokenize(text:String, transliteration:Transliteration = .hiragana)->[Annotation]{
        if self.isSystemTokenizer{
            return self.systemTokenizerTokenize(text: text, transliteration: transliteration)
        }
        else{
            return mecabTokenize(text: text, transliteration: transliteration)
        }
    }
    
    fileprivate func mecabTokenize(text:String, transliteration:Transliteration = .hiragana)->[Annotation]{
        let tokens=text.precomposedStringWithCanonicalMapping.withCString({s->[Token] in
           var tokens=[Token]()
           var node=mecab_sparse_tonode(self._mecab, s)
           while true{
               guard let n = node else {break}
           
                   if let token=Token(node: n.pointee, tokenDescription: self.dictionary){
                       tokens.append(token)
                   }
               
                   node = UnsafePointer(n.pointee.next)
           }
           return tokens
       })
       
      
       var annotations=[Annotation]()
       var searchRange=text.startIndex..<text.endIndex
       for token in tokens{
           let searchString=token.original
           if searchString.isEmpty{
               continue
           }
           if let foundRange=text.range(of: searchString, options: [], range: searchRange, locale: nil){
               let annotation=Annotation(token: token, range: foundRange, transliteration: transliteration)
               annotations.append(annotation)
               
               if foundRange.upperBound < text.endIndex{
                   searchRange=foundRange.upperBound..<text.endIndex
               }
           }
       }
   
       return annotations
    }
    
    
    /**
    A convenience function to tokenize text into `FuriganaAnnotations`.
     
     `FuriganaAnnotations` are meant for displaying furigana reading aids for Japanese Kanji characters, and consequently tokens that don't contain Kanji are skipped.
    - parameters:
       - text: A `string` that contains the text to tokenize.
       - transliteration : A `Transliteration` method. The text content of found tokens will be displayed using this.
       - options : Options to pass to the tokenizer
    - returns: An array of `FuriganaAnnotations`, which contain the reading o fthe token and the range of the token in the original text.
    */
    public func furiganaAnnotations(for text:String, transliteration:Transliteration = .hiragana, options:[Annotation.AnnotationOption] = [.kanjiOnly])->[FuriganaAnnotation]{
        
        return self.tokenize(text: text, transliteration: transliteration)
            .filter({$0.base.isEmpty == false})
            .compactMap({$0.furiganaAnnotation(options: options, for: text)})
            .flatMap({ $0 })
    }
    
    /**
       A convenience function to add `<ruby>` tags to  text.
        
        `<ruby>` tags are added to all tokens that contain Kanji characters, regardless of whether they are on specific parts of an HTML document or not. This can potentially disrupt scripts or navigation.
       - parameters:
          - htmlText: A `string` that contains the text to tokenize.
          - transliteration: A `Transliteration` method. The text content of found tokens will be displayed using this.
          - options: Options to pass to the tokenizer
       - returns: A text with `<ruby>` annotations.
       */
    public func addRubyTags(to htmlText:String, transliteration:Transliteration = .hiragana, options:[Annotation.AnnotationOption] = [.kanjiOnly])->String{
        let furigana=self.furiganaAnnotations(for: htmlText, transliteration: transliteration, options: options)
        var outString=""
        var endIDX = htmlText.startIndex
        
        for annotation in furigana{
            outString += htmlText[endIDX..<annotation.range.lowerBound]
            
            let original = htmlText[annotation.range]
            let htmlRuby="<ruby>\(original)<rt>\(annotation.reading)</rt></ruby>"
            outString += htmlRuby
            endIDX = annotation.range.upperBound
        }
        
        outString += htmlText[endIDX..<htmlText.endIndex]
        
        return outString
    
    }

    public typealias FTS5TokenCallback = @convention(c) (
        _ context: UnsafeMutableRawPointer?,
        _ flags: CInt,
        _ pToken: UnsafePointer<CChar>?,
        _ nToken: CInt,
        _ iStart: CInt,
        _ iEnd: CInt)
        -> CInt

    @discardableResult
    public func fts5(
        context: UnsafeMutableRawPointer?,
        pText: UnsafePointer<CChar>,
        nText: CInt,
        tokenCallback: FTS5TokenCallback
    ) -> CInt {
        var nlen: Int = 0
        var tmp: UnsafeMutablePointer<CChar>
        var buffer: UnsafeMutablePointer<CChar>
        var bufferLength: Int = 256
        var offset: CInt = 0
        var rc: CInt = 0
        
        buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Int(bufferLength))
        var node: mecab_node_t? = mecab_sparse_tonode(_mecab, pText).pointee
        guard var node = node else { return 0 }
        if String(cString: node.surface).isEmpty { return 0 }
        while node != nil {
            while node.next != nil && node.length == 0 {
                offset += CInt(node.rlength)
                node = node.next.pointee
            }
            nlen = Int(node.length)
            offset += Int32((Int(node.rlength) - nlen))
            if nlen > bufferLength {
                let tmp = UnsafeMutablePointer<CChar>.allocate(capacity: nlen + 1)
                tmp.initialize(from: buffer, count: nlen)
                buffer.deallocate()
                buffer = tmp
                buffer[nlen] = 0
                bufferLength = nlen
            }
            strncpy(buffer, node.surface, nlen)
            buffer[nlen] = 0
//            print("match token: \(String(cString: buffer))")
            rc = tokenCallback(context, 0, buffer, CInt(nlen), offset, offset + CInt(nlen))
            
            if rc != 0 {
                break
            }
            offset += Int32(node.length)
            node = node.next.pointee
            if offset >= nText {
                rc = 0
                break
            }
        }
        while node != nil && node.next != nil {
            node = node.next.pointee
        }
        nlen = 0
        buffer.deallocate()
        bufferLength = 0
        offset = 0
        return rc
    }

    deinit {
        mecab_destroy(_mecab)
    }

}


//if let lowerBound = outString.index(tokenRange.lowerBound, offsetBy: htmlRuby.count, limitedBy: outString.endIndex){
//    searchRange = lowerBound ..< outString.endIndex
//}
//else{
//    continue
//}






