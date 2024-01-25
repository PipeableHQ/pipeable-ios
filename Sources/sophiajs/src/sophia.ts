(function () {
    class SophiaPage {
        private elementRegistry = new WeakDomRegistry();

        private xhrHandles: {
            [key: string]: { resolve: (res: XHRResult) => void; reject: (error: string) => void }[];
        } = {};

        constructor() {
            console.log('SophiaJS constructor for frame with url ' + window.location.href);

            // this.attachScriptEventListener();
            this.attachXHRListener();
            this.attachFetchListener();

            this.attachOnErrorListener();
            this.attachMessageBus();
        }

        $(selector: string, parentElementHash?: string): string | null {
            let parentNode: ParentNode;

            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            } else {
                parentNode = document;
            }

            const el = parentNode.querySelector(selector);
            if (el) {
                return this.wrapHandle(el as HTMLElement);
            } else {
                return null;
            }
        }

        $$(selector: string, parentElementHash?: string): string[] {
            let parentNode: ParentNode;

            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            } else {
                parentNode = document;
            }

            const elements = parentNode.querySelectorAll(selector);
            const sophiaEls: string[] = [];
            for (let i = 0; i < elements.length; i++) {
                const el = elements[i];
                sophiaEls.push(this.wrapHandle(el as HTMLElement));
            }

            return sophiaEls;
        }

        $x(xpath: string, parentElementHash?: string): string[] {
            let parentNode: ParentNode;

            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            } else {
                parentNode = document;
            }

            const elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const sophiaEls: string[] = [];
            for (let i = 0; i < elements.snapshotLength; i++) {
                const el = elements.snapshotItem(i);
                if (el) {
                    sophiaEls.push(this.wrapHandle(el as HTMLElement));
                }
            }

            return sophiaEls;
        }

        async waitForSelector(
            selector: string,
            opts?: { timeout?: number; visible?: boolean; parentElementHash?: string },
        ): Promise<string> {
            // console.log('got wait for selector ' + selector + ' for frame with url ' + window.location.href);

            let parentNode: ParentNode;

            if (opts?.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            } else {
                parentNode = document;
            }

            let el = parentNode.querySelector(selector);

            const timeout = opts?.timeout || 10_000;

            const start = Date.now();

            // console.log(
            //     'got el ',
            //     el,
            //     ' qualify for visibile=' + !!opts?.visible + ' ',
            //     qualifyElement(el, !!opts?.visible),
            // );

            while (!qualifyElement(el, !!opts?.visible)) {
                if (Date.now() - start > timeout) {
                    throw new Error(`Timeout waiting for selector ${selector}`);
                }

                await new Promise((resolve) => setTimeout(resolve, 500));

                // Re-evaluate
                el = parentNode.querySelector(selector);

                // console.log(
                //     'got el ',
                //     el,
                //     ' qualify for visibile=' + !!opts?.visible + ' ',
                //     qualifyElement(el, !!opts?.visible),
                // );
            }

            return this.wrapHandle(el as HTMLElement);
        }

        async waitForXPath(
            xpath: string,
            opts?: { timeout?: number; visible?: boolean; parentElementHash?: string },
        ): Promise<string> {
            let parentNode: ParentNode;

            if (opts?.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            } else {
                parentNode = document;
            }

            let elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);

            const timeout = opts?.timeout || 10_000;

            const start = Date.now();

            while (!qualifyElement(elements.snapshotItem(0) as HTMLElement, !!opts?.visible)) {
                if (Date.now() - start > timeout) {
                    throw new Error(`Timeout waiting for xpath ${xpath}`);
                }

                await new Promise((resolve) => setTimeout(resolve, 500));

                // Re-evaluate
                elements = document.evaluate(xpath, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            }

            return this.wrapHandle(elements.snapshotItem(0) as HTMLElement);
        }

        async waitForXHR(url: string, opts?: { timeout?: number }): Promise<string> {
            this.xhrHandles[url] = this.xhrHandles[url] || [];
            const timeout = opts?.timeout || 30_000;

            console.log('[' + window.location.href + '] ADDED WAITING HANDLE FOR ' + url);

            return new Promise<string>((resolve, reject) => {
                const timeoutId = setTimeout(() => {
                    reject(`Timeout waiting for XHR ${url}`);
                }, timeout);

                const handle = {
                    resolve: (res: XHRResult) => {
                        console.log('[' + window.location.href + '] RECEIVED RESOLVE FOR ' + url);
                        clearTimeout(timeoutId);
                        resolve(JSON.stringify(res));
                        this.xhrHandles[url] = this.xhrHandles[url].filter((h) => h !== handle);
                        if (this.xhrHandles[url].length === 0) {
                            delete this.xhrHandles[url];
                        }
                    },
                    reject: (error: string) => {
                        clearTimeout(timeoutId);
                        reject(error);
                        this.xhrHandles[url] = this.xhrHandles[url].filter((h) => h !== handle);
                        if (this.xhrHandles[url].length === 0) {
                            delete this.xhrHandles[url];
                        }
                    },
                };

                this.xhrHandles[url].push(handle);
            });
        }

        click(elementHash: string) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                const event = new MouseEvent('click', {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                });

                el.dispatchEvent(event);

                // TODO: Do we need to issue the browser click here or is dispatching the click event enough?
                // (el as HTMLElement).click();

                return true;
            }

            return false;
        }

        focus(elementHash: string) {
            const el = this.elementRegistry.get(elementHash);

            if (el) {
                // emit focus event.
                const event = new FocusEvent('focus', {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                });

                el.dispatchEvent(event);
                el.focus();

                return true;
            }

            return false;
        }

        blur(elementHash: string) {
            const el = this.elementRegistry.get(elementHash);

            if (el) {
                // emit blur event.

                const event = new FocusEvent('blur', {
                    view: window,
                    bubbles: true,
                    cancelable: true,
                });

                el.dispatchEvent(event);

                el.blur();

                return true;
            }

            return false;
        }

        textContent(elementHash: string): string | null {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.textContent;
            }

            return null;
        }

        getAttribute(elementHash: string, attributeName: string): string | null {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.getAttribute(attributeName);
            }

            return null;
        }

        async type(elementHash: string, text: string, opts?: { delay?: number }) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                this.focus(elementHash);

                const delay = opts?.delay || 0;

                for (let i = 0; i < text.length; i++) {
                    const event = new KeyboardEvent('keydown', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });

                    el.dispatchEvent(event);

                    if (delay > 0) {
                        await new Promise((resolve) => setTimeout(resolve, delay));
                    }

                    const event2 = new KeyboardEvent('keypress', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });

                    el.dispatchEvent(event2);

                    const event3 = new KeyboardEvent('keyup', {
                        view: window,
                        bubbles: true,
                        cancelable: true,
                        key: text[i],
                        code: text[i],
                        charCode: text.charCodeAt(i),
                        keyCode: text.charCodeAt(i),
                    });

                    el.dispatchEvent(event3);

                    // Emulate input event
                    let inputEvent = new Event('input', { bubbles: true });
                    el.dispatchEvent(inputEvent);

                    document.execCommand('insertText', false, text[i]);
                    // (el as HTMLInputElement).value = text.slice(0, i + 1);
                }

                this.blur(elementHash);
            }
        }

        sendFrameIDMessage(elementHash: string, requestId: string): boolean {
            const el = this.elementRegistry.get(elementHash);
            if (!el) {
                return false;
            }

            // TODO: Perhaps needs a different error message to differentiate.
            if (el.tagName.toLowerCase() !== 'iframe') {
                return false;
            }

            // It's an iframe. We can post a message to get the ID and associate it with the calling request.
            const iframe = el as HTMLIFrameElement;
            const message = { ctx: 'sophia', payload: { requestId: requestId } };
            iframe.contentWindow!.postMessage(JSON.stringify(message), '*');

            return true;
        }

        private wrapHandle(el: HTMLElement): string {
            let retries = 0;
            do {
                const hash = generateShortRandomHash();
                if (!this.elementRegistry.has(hash)) {
                    this.elementRegistry.set(hash, el);
                    return hash;
                }

                retries++;

                if (retries > 100) {
                    throw new Error('Failed to generate unique hash');
                }
            } while (true);
        }

        version() {
            window.webkit.messageHandlers.handler.postMessage({
                method: 'version',
                requestId: 'asd',
                payload: { version: '0.0.1' },
            });
        }

        private attachOnErrorListener() {
            window.onerror = function (message, source, lineno, colno, error) {
                var errorInfo = {
                    message: message,
                    source: source,
                    lineno: lineno,
                    colno: colno,
                    error: error,
                };
                window.webkit.messageHandlers.handler.postMessage({
                    payload: {
                        error: JSON.stringify(errorInfo),
                    },
                });
            };
        }

        private attachMessageBus() {
            // Are we in an iframe?
            if (window.self !== window.top) {
                // If so, listen for messages from the parent window

                window.addEventListener(
                    'message',
                    function (event) {
                        try {
                            const data = JSON.parse(event.data);
                            if (data.ctx === 'sophia') {
                                // Forward message to native.
                                window.webkit.messageHandlers.handler.postMessage({
                                    ctx: 'sophia',
                                    name: 'frameInfoId',
                                    payload: data.payload,
                                });
                            }
                        } catch (e) {
                            console.log('Error parsing message', e);
                        }

                        // window.webkit.messageHandlers.handler.postMessage({
                        //     payload: {
                        //         name: 'frameMessage',
                        //         data: event.data,
                        //     }
                        // });
                    },
                    false,
                );
            } else {
                // If not, listen for messages from the iframe

                window.addEventListener('message', function (event) {
                    try {
                        const data = JSON.parse(event.data);
                        if (data.ctx === 'sophia') {
                            // You can send the received data to Swift using WKScriptMessageHandler here
                            window.webkit.messageHandlers.handler.postMessage({
                                payload: {
                                    name: 'parentMessage',
                                    data: event.data,
                                },
                            });
                        }
                    } catch (e) {
                        console.log('Error parsing message: ' + JSON.stringify(event));
                    }
                });
            }
        }

        // private attachScriptEventListener() {
        //     const observer = new MutationObserver(function (mutations) {
        //         mutations.forEach(function (mutation) {
        //             if (mutation.type === 'childList') {
        //                 for (let i = 0; i < mutation.addedNodes.length; i++) {
        //                     var node = mutation.addedNodes[i] as any;
        //                     if (node.tagName === 'SCRIPT' && node.src) {
        //                         const origOnload = node.onload?.bind(node);

        //                         var message = { payload: { scriptUrl: node.src } };

        //                         node.onload = function () {
        //                             if (origOnload) {
        //                                 origOnload();
        //                             }

        //                             window.webkit.messageHandlers.handler.postMessage(message);
        //                         };
        //                     }
        //                 }
        //             }
        //         });
        //     });

        //     observer.observe(document, {
        //         childList: true,
        //         subtree: true,
        //     });

        //     // Once found and attached, we can stop observing
        //     // observer.disconnect();

        //     console.log('Attached MutationObserver to listen for script loads.');
        // }

        private handleXHRResult(xhrResult: XHRResult) {
            console.log('[' + document.location.href + '] Handling XHR Url for: ' + xhrResult.url);

            const reqUrl = xhrResult.url;

            for (let url in this.xhrHandles) {
                const handles = this.xhrHandles[url];
                if (handles?.length > 0 && reqUrl.toLowerCase().includes(url.toLowerCase())) {
                    for (let i = 0; i < handles.length; i++) {
                        handles[i].resolve(xhrResult);
                    }
                }
            }
        }

        private attachXHRListener() {
            var originalXMLHttpRequest = window.XMLHttpRequest;
            const self = this;

            window.XMLHttpRequest = function () {
                var req = new originalXMLHttpRequest();

                req.addEventListener('loadstart', function () {
                    console.log('[REQUEST START] ' + req.responseURL);
                    return true;
                });

                req.addEventListener('loadend', function () {
                    const status = req.status;
                    const bodyRaw = req.response;
                    let body: string;

                    const contentType = req.getResponseHeader('content-type');
                    const isJson = contentType?.includes('application/json') || contentType?.includes('text/json');

                    if (req.responseType === '' || req.responseType === 'text') {
                        body = req.responseText;
                    } else if (req.responseType === 'json') {
                        body = JSON.stringify(req.response);
                    } else if (req.responseType === 'document') {
                        body = req.response.documentElement.outerHTML;
                    } else if (req.responseType === 'arraybuffer' || req.responseType === 'blob') {
                        if (isJson) {
                            // Convert the array buffer to text and return the text to be parsed as JSON.
                            body = new TextDecoder('utf-8').decode(bodyRaw);
                        } else {
                            // Convert ArrayBuffer to Base64 or other textual format
                            body = btoa(String.fromCharCode.apply(null, new Uint8Array(bodyRaw)));
                        }
                    } else {
                        throw new Error('Unsupported response type: ' + req.responseType);
                    }

                    const headers = req.getAllResponseHeaders();

                    const xhrResult: XHRResult = {
                        status: status,
                        url: req.responseURL,
                        body: body,
                        responseType: req.responseType,
                        headers: headers,
                    };

                    console.log('[REQUEST END] ' + req.responseURL, xhrResult);

                    // Dispatch to queue.
                    self.handleXHRResult(xhrResult);
                    // var message = { payload: { url: (event?.currentTarget as any).responseURL } };
                    // window.webkit.messageHandlers.handler.postMessage(message);

                    return true;
                });

                // TODO: Add error handling here.
                // req.addEventListener('error', function (event) {
                //     var message = { payload: { url: (event?.currentTarget as any).responseURL } };
                //     window.webkit.messageHandlers.handler.postMessage(message);
                // });

                // req.addEventListener('abort', function (event) {});

                return req;
            } as unknown as typeof XMLHttpRequest;
            window.XMLHttpRequest.prototype = originalXMLHttpRequest.prototype;

            // const originalOpen = XMLHttpRequest.prototype.open;

            // XMLHttpRequest.prototype.open = function (method: string, url: string, ...args: any[]) {
            //     // Store the method and URL for later retrieval
            //     this._method = method;
            //     this._requestURL = url;

            //     originalOpen.apply(this, args);
            // } as unknown as typeof XMLHttpRequest.prototype.open;

            console.log('Attached XHR listener.');
        }

        private attachFetchListener() {
            const self = this;

            const originalFetch = window.fetch;

            window.fetch = async function (...args) {
                console.log('Fetching:', args); // or any other custom event/logic

                try {
                    const response = await originalFetch(...args);

                    // Clone the response so we can read it and still return the original
                    const clone = response.clone();

                    // const contentType = clone.headers.get('content-type');
                    const responseBody = await clone.text();

                    const headersArray: string[] = [];
                    response.headers.forEach((value, name) => {
                        headersArray.push(name + ': ' + value);
                    });

                    const xhrResult: XHRResult = {
                        status: response.status,
                        url: response.url,
                        body: responseBody,
                        headers: headersArray.join('\n'),
                        responseType: 'text',
                    };

                    self.handleXHRResult(xhrResult);
                    console.log(xhrResult);

                    return response;
                } catch (error) {
                    console.error('Fetch error:', error);
                    throw error;
                }
            };
        }
    }

    class WeakDomRegistry {
        private keyToObjectMap: Map<string, object>;
        private objectToDomMap: WeakMap<object, HTMLElement>;

        constructor() {
            this.keyToObjectMap = new Map(); // Maps strings to objects
            this.objectToDomMap = new WeakMap(); // Maps objects to DOM elements
        }

        set(id: string, element: HTMLElement) {
            let keyObject = {};
            this.keyToObjectMap.set(id, keyObject);
            this.objectToDomMap.set(keyObject, element);
        }

        get(id: string): HTMLElement | undefined {
            let keyObject = this.keyToObjectMap.get(id);
            if (keyObject) {
                const el = this.objectToDomMap.get(keyObject);
                if (el) {
                    if (!el.isConnected) {
                        throw new Error('Element not attached to DOM');
                    }

                    return el;
                }
            }

            return undefined;
        }

        delete(id: string) {
            let keyObject = this.keyToObjectMap.get(id);
            if (keyObject) {
                this.objectToDomMap.delete(keyObject);
                this.keyToObjectMap.delete(id);
            }
        }

        has(id: string): boolean {
            return this.keyToObjectMap.has(id) && this.objectToDomMap.has(this.keyToObjectMap.get(id)!);
        }
    }

    function generateShortRandomHash(length: number = 6) {
        const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        let result = '';

        for (let i = 0; i < length; i++) {
            result += chars[Math.floor(Math.random() * chars.length)];
        }

        return result;
    }

    function isElementAttached(el: Element) {
        return document.body.contains(el);
    }

    function isElementVisible(el: Element) {
        let currentElement: Element | null = el;

        // Check element style and its ancestors
        while (currentElement) {
            const style = getComputedStyle(currentElement);
            if (
                style.display === 'none' ||
                style.visibility === 'hidden' ||
                parseFloat(style.opacity) === 0 ||
                style.width === '0' ||
                style.height === '0'
            ) {
                return false;
            }
            currentElement = currentElement.parentElement;
        }

        return true;
    }

    function qualifyElement(element: Element | null, visible: boolean) {
        if (element) {
            if (visible && !isElementVisible(element)) {
                // console.log('Disqualified element because it is not visible');
                return false;
            }

            if (!isElementAttached(element)) {
                // console.log('Disqualified element because it is not attached');
                return false;
            }

            return true;
        }

        // console.log('Disqualified element because it is null');

        return false;
    }

    type XHRResult = {
        status: number;
        url: string;
        body: string;
        headers: string;
        responseType: XMLHttpRequestResponseType;
    };

    // Expose this directly.
    if (!(window as any).SophiaJS) {
        (window as any).SophiaJS = new SophiaPage();
    }
})();
