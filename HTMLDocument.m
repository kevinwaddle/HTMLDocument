/*###################################################################################
 #																					#
 #    HTMLDocument.m																#
 #																					#
 #    Copyright © 2011 by Stefan Klieme                                             #
 #																					#
 #	  Objective-C wrapper for HTML parser of libxml2								#
 #																					#
 #	  Version 1.1 - 3. Apr 2012                                                     #
 #																					#
 #    usage:     add libxml2.dylib to frameworks                                    #
 #               add $SDKROOT/usr/include/libxml2 to target -> Header Search Paths  #
 #               add -lxml2 to target -> other linker flags                         #
 #                                                                                  #
 #																					#
 ####################################################################################
 #																					#
 # Permission is hereby granted, free of charge, to any person obtaining a copy of  #
 # this software and associated documentation files (the "Software"), to deal       #
 # in the Software without restriction, including without limitation the rights     #
 # to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies #
 # of the Software, and to permit persons to whom the Software is furnished to do   #
 # so, subject to the following conditions:                                         #
 # The above copyright notice and this permission notice shall be included in       #
 # all copies or substantial portions of the Software.                              #
 # THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR       #
 # IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,         #
 # FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE      #
 # AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,# 
 # WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR     #
 # IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.	#
 #																					#
 ###################################################################################*/

#import "HTMLDocument.h"

@implementation HTMLDocument
@synthesize rootNode;

#pragma mark - class methods

// convenience initializer methods

+ (HTMLDocument *)documentWithData:(NSData *)data encoding:(NSStringEncoding )encoding error:(NSError **)error
{
    return [[HTMLDocument alloc] initWithData:data encoding:encoding error:error];
}

+ (HTMLDocument *)documentWithData:(NSData *)data error:(NSError **)error
{
    return [[HTMLDocument alloc] initWithData:data error:error];
}

+ (HTMLDocument *)documentWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding )encoding error:(NSError **)error
{
     return [[HTMLDocument alloc] initWithContentsOfURL:url encoding:encoding error:error];
}

+ (HTMLDocument *)documentWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
    return [[HTMLDocument alloc] initWithContentsOfURL:url error:error];
}

+ (HTMLDocument *)documentWithHTMLString:(NSString *)string encoding:(NSStringEncoding )encoding error:(NSError **)error
{
     return [[HTMLDocument alloc] initWithHTMLString:string encoding:encoding error:error];
}

+ (HTMLDocument *)documentWithHTMLString:(NSString *)string error:(NSError **)error
{
    return [[HTMLDocument alloc] initWithHTMLString:string error:error];
}

#pragma mark - instance init methods

// designated initializer
- (id)initWithData:(NSData *)data encoding:(NSStringEncoding )encoding error:(NSError **)error
{
    self = [super init];
    if (self) {
        NSInteger errorCode = 0;
		if (data && [data length]) {
            CFStringEncoding cfEncoding = CFStringConvertNSStringEncodingToEncoding(encoding);
            CFStringRef cfEncodingAsString = CFStringConvertEncodingToIANACharSetName(cfEncoding);
            const char *cfEncodingStringPtr = CFStringGetCStringPtr(cfEncodingAsString, kCFStringEncodingMacRoman);
            
            int htmlParseOptions = HTML_PARSE_RECOVER | HTML_PARSE_NOERROR | HTML_PARSE_NOWARNING;
            htmlDoc_ = htmlReadDoc(BAD_CAST [data bytes], NULL, cfEncodingStringPtr, htmlParseOptions);
            if (htmlDoc_) {
                xmlNodePtr xmlDocRootNode = xmlDocGetRootElement(htmlDoc_);
                if (xmlDocRootNode && xmlStrEqual(xmlDocRootNode->name, BAD_CAST "html")) {
                    rootNode = [[HTMLNode alloc] initWithXMLNode:xmlDocRootNode];
                }
                else
                    errorCode = 3;
            }
            else
                errorCode = 2;
		}
		else 
            errorCode = 1;
        
        if (errorCode) {
            if (error) 
                *error = [self errorForCode:errorCode];
            
            return nil;
        }
    }
	return self;
}

- (id)initWithData:(NSData *)data error:(NSError **)error
{
	return [self initWithData:data encoding:NSUTF8StringEncoding error:error];
}

- (id)initWithContentsOfURL:(NSURL *)url encoding:(NSStringEncoding )encoding error:(NSError **)error
{
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
    if (data && *error == nil) {
        return [self initWithData:data encoding:encoding error:error];
    }
	return nil;
}

- (id)initWithContentsOfURL:(NSURL *)url error:(NSError **)error
{
	return [self initWithContentsOfURL:url encoding:NSUTF8StringEncoding error:error];
}

- (id)initWithHTMLString:(NSString *)string encoding:(NSStringEncoding )encoding error:(NSError **)error
{ 
	return [self initWithData:[string dataUsingEncoding:encoding] 
                     encoding:encoding 
                        error:error];
}

- (id)initWithHTMLString:(NSString *)string error:(NSError **)error
{
	return [self initWithHTMLString:string encoding:NSUTF8StringEncoding error:error];
}


- (void)dealloc
{
    xmlFreeDoc(htmlDoc_);
}

#pragma mark - frequently used nodes

- (HTMLNode *)head
{	
	return [self.rootNode childOfTag:@"head"];
}

- (HTMLNode *)body
{	
	return [self.rootNode childOfTag:@"body"];
}

- (NSString *)title
{	
	return [[self.head childOfTag:@"title"] stringValue];
}

#pragma mark - error handling

- (NSError *)errorForCode:(NSInteger )errorCode
{
    NSString *errorString = nil;
    switch (errorCode) {
        case 1:
            errorString = @"No valid data";
            break;
            
        case 2:
            errorString = @"XML data could not be parsed";
            break;
            
        case 3:
            errorString = @"XML data seems not to be of type HTML";
            break;
    }
    return [NSError errorWithDomain:@"com.klieme.HTMLDocument"
                        code:errorCode 
                    userInfo:[NSDictionary dictionaryWithObject:errorString forKey:NSLocalizedDescriptionKey]];
}


@end
