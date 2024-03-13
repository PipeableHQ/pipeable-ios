"use strict";
(function () {
    class SophiaPage {
        constructor() {
            this.elementRegistry = new WeakDomRegistry();
            this.xhrHandles = {};
            this.neworkIdleMonitor = new NetworkActivityMonitor();
            console.log('SophiaJS constructor for frame with url ' + window.location.href);
            // this.attachScriptEventListener();
            this.attachXHRListener();
            this.attachFetchListener();
            this.attachOnErrorListener();
            this.attachMessageBus();
            this.attachOnLoadListeners();
        }
        $(selector, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const el = parentNode.querySelector(selector);
            if (el) {
                return this.wrapHandle(el);
            }
            else {
                return null;
            }
        }
        $$(selector, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const elements = parentNode.querySelectorAll(selector);
            const sophiaEls = [];
            for (let i = 0; i < elements.length; i++) {
                const el = elements[i];
                sophiaEls.push(this.wrapHandle(el));
            }
            return sophiaEls;
        }
        $x(xpath, parentElementHash) {
            let parentNode;
            if (parentElementHash) {
                const parentEl = this.elementRegistry.get(parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            const elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const sophiaEls = [];
            for (let i = 0; i < elements.snapshotLength; i++) {
                const el = elements.snapshotItem(i);
                if (el) {
                    sophiaEls.push(this.wrapHandle(el));
                }
            }
            return sophiaEls;
        }
        async waitForSelector(selector, opts) {
            console.log('got wait for selector ' + selector + ' for frame with url ' + window.location.href);
            let parentNode;
            if (opts === null || opts === void 0 ? void 0 : opts.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            let el = parentNode.querySelector(selector);
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 10000;
            const start = Date.now();
            // console.log(
            //     'got el ',
            //     el,
            //     ' qualify for visibile=' + !!opts?.visible + ' ',
            //     qualifyElement(el, !!opts?.visible),
            // );
            while (!qualifyElement(el, !!(opts === null || opts === void 0 ? void 0 : opts.visible))) {
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
            return this.wrapHandle(el);
        }
        async waitForXPath(xpath, opts) {
            let parentNode;
            if (opts === null || opts === void 0 ? void 0 : opts.parentElementHash) {
                const parentEl = this.elementRegistry.get(opts.parentElementHash);
                parentNode = parentEl || document;
            }
            else {
                parentNode = document;
            }
            let elements = document.evaluate(xpath, parentNode, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 10000;
            const start = Date.now();
            while (!qualifyElement(elements.snapshotItem(0), !!(opts === null || opts === void 0 ? void 0 : opts.visible))) {
                if (Date.now() - start > timeout) {
                    throw new Error(`Timeout waiting for xpath ${xpath}`);
                }
                await new Promise((resolve) => setTimeout(resolve, 500));
                // Re-evaluate
                elements = document.evaluate(xpath, document, null, XPathResult.ORDERED_NODE_SNAPSHOT_TYPE, null);
            }
            return this.wrapHandle(elements.snapshotItem(0));
        }
        async waitForXHR(url, opts) {
            this.xhrHandles[url] = this.xhrHandles[url] || [];
            const timeout = (opts === null || opts === void 0 ? void 0 : opts.timeout) || 30000;
            console.log('[' + window.location.href + '] ADDED WAITING HANDLE FOR ' + url);
            return new Promise((resolve, reject) => {
                const timeoutId = setTimeout(() => {
                    reject(`Timeout waiting for XHR ${url}`);
                }, timeout);
                const handle = {
                    resolve: (res) => {
                        console.log('[' + window.location.href + '] RECEIVED RESOLVE FOR ' + url);
                        clearTimeout(timeoutId);
                        resolve(JSON.stringify(res));
                        this.xhrHandles[url] = this.xhrHandles[url].filter((h) => h !== handle);
                        if (this.xhrHandles[url].length === 0) {
                            delete this.xhrHandles[url];
                        }
                    },
                    reject: (error) => {
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
        async click(elementHash, opts) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                // Wait until the element becomes visible.
                const start = Date.now();
                while (!qualifyElement(el, true)) {
                    if (Date.now() - start > opts.timeout) {
                        throw new Error(`Timed out waiting for element to become visible to click: ${elementHash}`);
                    }
                    await new Promise((resolve) => setTimeout(resolve, 100));
                }
                if ('scrollIntoViewIfNeeded' in el) {
                    // this seems to be available in Safari, but for some of the other browser we may need to polyfill.
                    // https://github.com/nuxodin/lazyfill/blob/main/polyfills/Element/prototype/scrollIntoViewIfNeeded.js
                    el.scrollIntoViewIfNeeded();
                }
                else {
                    el.scrollIntoView();
                }
                // Get the bounding rectangle of the visible area of the element
                const rect = el.getBoundingClientRect();
                // Calculate the coordinates of the center of the visible area of the element
                const centerX = rect.left + rect.width / 2;
                const centerY = rect.top + rect.height / 2;
                // Get the innermost element covering the center of the visible area
                const innermostElement = document.elementFromPoint(centerX, centerY);
                // Dispatch a click event on the innermost element
                const clickEvent = new MouseEvent('click', {
                    bubbles: true,
                    cancelable: true,
                    view: window,
                    screenX: window.screenX + centerX,
                    screenY: window.screenY + centerY,
                    clientX: window.screenX + centerX,
                    clientY: window.screenY + centerY,
                    ctrlKey: false,
                    altKey: false,
                    shiftKey: false,
                    metaKey: false,
                    button: 0,
                    relatedTarget: null,
                });
                if (!innermostElement) {
                    throw new Error('No innermost element found at the center of the original element -- should not happen');
                }
                // console.log(
                //     'Dispatching click event on innermost element: ' +
                //         innermostElement.tagName +
                //         '#' +
                //         innermostElement.id,
                // );
                innermostElement.dispatchEvent(clickEvent);
                return true;
            }
            return false;
        }
        focus(elementHash) {
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
        blur(elementHash) {
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
        textContent(elementHash) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.textContent;
            }
            return null;
        }
        getAttribute(elementHash, attributeName) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                return el.getAttribute(attributeName);
            }
            return null;
        }
        getElement(elementHash) {
            return this.elementRegistry.get(elementHash);
        }
        submitActiveForm() {
            // Find the currently active element, then the closest form and submit it.
            // If there is no such form or no active element, return false.
            const activeElement = document.activeElement;
            if (!activeElement) {
                return false;
            }
            const form = activeElement.closest('form');
            if (!form) {
                return false;
            }
            const event = new Event('submit', {
                bubbles: true,
                cancelable: true,
            });
            // Dispatch the event
            if (form.dispatchEvent(event)) {
                // If the event was not cancelled, submit the form
                form.submit();
            }
            return true;
        }
        async type(elementHash, text, opts) {
            const el = this.elementRegistry.get(elementHash);
            if (el) {
                this.focus(elementHash);
                const delay = (opts === null || opts === void 0 ? void 0 : opts.delay) || 0;
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
            }
        }
        sendFrameIDMessage(elementHash, requestId) {
            const el = this.elementRegistry.get(elementHash);
            if (!el) {
                return false;
            }
            // TODO: Perhaps needs a different error message to differentiate.
            if (el.tagName.toLowerCase() !== 'iframe') {
                return false;
            }
            // It's an iframe. We can post a message to get the ID and associate it with the calling request.
            const iframe = el;
            const message = { ctx: 'sophia', payload: { requestId: requestId } };
            iframe.contentWindow.postMessage(JSON.stringify(message), '*');
            return true;
        }
        wrapHandle(el) {
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
        attachOnErrorListener() {
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
        attachMessageBus() {
            // Are we in an iframe?
            if (window.self !== window.top) {
                // If so, listen for messages from the parent window
                window.addEventListener('message', function (event) {
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
                    }
                    catch (e) {
                        console.log('Error parsing message', e);
                    }
                    // window.webkit.messageHandlers.handler.postMessage({
                    //     payload: {
                    //         name: 'frameMessage',
                    //         data: event.data,
                    //     }
                    // });
                }, false);
            }
            else {
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
                    }
                    catch (e) {
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
        handleXHRResult(xhrResult) {
            console.log('[' + document.location.href + '] Handling XHR Url for: ' + xhrResult.url);
            const reqUrl = xhrResult.url;
            for (let url in this.xhrHandles) {
                const handles = this.xhrHandles[url];
                if ((handles === null || handles === void 0 ? void 0 : handles.length) > 0 && reqUrl.toLowerCase().includes(url.toLowerCase())) {
                    for (let i = 0; i < handles.length; i++) {
                        handles[i].resolve(xhrResult);
                    }
                }
            }
        }
        attachXHRListener() {
            var originalXMLHttpRequest = window.XMLHttpRequest;
            const self = this;
            window.XMLHttpRequest = function () {
                var req = new originalXMLHttpRequest();
                req.addEventListener('loadstart', function () {
                    console.log('[REQUEST START] ' + req.responseURL);
                    self.neworkIdleMonitor.onRequestStart();
                    return true;
                });
                req.addEventListener('loadend', function () {
                    const status = req.status;
                    const bodyRaw = req.response;
                    let body;
                    const contentType = req.getResponseHeader('content-type');
                    const isJson = (contentType === null || contentType === void 0 ? void 0 : contentType.includes('application/json')) || (contentType === null || contentType === void 0 ? void 0 : contentType.includes('text/json'));
                    if (req.responseType === '' || req.responseType === 'text') {
                        body = req.responseText;
                    }
                    else if (req.responseType === 'json') {
                        body = JSON.stringify(req.response);
                    }
                    else if (req.responseType === 'document') {
                        body = req.response.documentElement.outerHTML;
                    }
                    else if (req.responseType === 'arraybuffer' || req.responseType === 'blob') {
                        if (isJson) {
                            // Convert the array buffer to text and return the text to be parsed as JSON.
                            body = new TextDecoder('utf-8').decode(bodyRaw);
                        }
                        else {
                            // Convert ArrayBuffer to Base64 or other textual format
                            body = btoa(String.fromCharCode.apply(null, new Uint8Array(bodyRaw)));
                        }
                    }
                    else {
                        throw new Error('Unsupported response type: ' + req.responseType);
                    }
                    const headers = req.getAllResponseHeaders();
                    const xhrResult = {
                        status: status,
                        url: req.responseURL,
                        body: body,
                        responseType: req.responseType,
                        headers: headers,
                    };
                    self.neworkIdleMonitor.onRequestEnd();
                    console.log('[REQUEST END] ' + req.responseURL, xhrResult);
                    // Dispatch to queue.
                    self.handleXHRResult(xhrResult);
                    // var message = { payload: { url: (event?.currentTarget as any).responseURL } };
                    // window.webkit.messageHandlers.handler.postMessage(message);
                    return true;
                });
                req.addEventListener('error', function (_) {
                    self.neworkIdleMonitor.onRequestEnd();
                    // TODO: Add error handling here.
                });
                req.addEventListener('abort', function (_) {
                    self.neworkIdleMonitor.onRequestEnd();
                    // TODO: Add error handling here.
                });
                return req;
            };
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
        attachFetchListener() {
            const self = this;
            const originalFetch = window.fetch;
            window.fetch = async function (...args) {
                console.log('Fetching:', args); // or any other custom event/logic
                self.neworkIdleMonitor.onRequestStart();
                try {
                    const response = await originalFetch(...args);
                    // Clone the response so we can read it and still return the original
                    const clone = response.clone();
                    // const contentType = clone.headers.get('content-type');
                    const responseBody = await clone.text();
                    const headersArray = [];
                    response.headers.forEach((value, name) => {
                        headersArray.push(name + ': ' + value);
                    });
                    const xhrResult = {
                        status: response.status,
                        url: response.url,
                        body: responseBody,
                        headers: headersArray.join('\n'),
                        responseType: 'text',
                    };
                    self.handleXHRResult(xhrResult);
                    console.log(xhrResult);
                    return response;
                }
                catch (error) {
                    console.error('Fetch error:', error);
                    throw error;
                }
                finally {
                    self.neworkIdleMonitor.onRequestEnd();
                }
            };
        }
        attachOnLoadListeners() {
            window.addEventListener('DOMContentLoaded', () => {
                var _a, _b, _c;
                console.log('SophiaJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'sophia',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'domcontentloaded',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
            });
            window.addEventListener('load', () => {
                var _a, _b, _c;
                console.log('SophiaJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'sophia',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'load',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
                // Once we're loaded, we start monitoring network activity and wait until it's idle.
                this.neworkIdleMonitor.start();
            });
            this.neworkIdleMonitor.setOnIdle(() => {
                var _a, _b, _c;
                console.log('SophiaJS networkidle event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'sophia',
                    name: 'pageLoadStateChange',
                    payload: {
                        state: 'networkidle',
                        url: window.location.href,
                    },
                };
                (_c = (_b = (_a = window.webkit) === null || _a === void 0 ? void 0 : _a.messageHandlers) === null || _b === void 0 ? void 0 : _b.handler) === null || _c === void 0 ? void 0 : _c.postMessage(message);
            });
        }
    }
    class NetworkActivityMonitor {
        constructor() {
            this.requestsInFlight = 0;
            this.idleTimeout = 500;
            this.onIdle = () => { };
        }
        setOnIdle(onIdle) {
            this.onIdle = onIdle;
        }
        onRequestStart() {
            this.requestsInFlight++;
            this.resetIdleTimeout();
        }
        onRequestEnd() {
            this.requestsInFlight--;
            this.resetIdleTimeout();
        }
        start() {
            this.resetIdleTimeout();
        }
        resetIdleTimeout() {
            if (this.timeoutId) {
                clearTimeout(this.timeoutId);
            }
            if (this.requestsInFlight === 0) {
                this.timeoutId = setTimeout(() => {
                    this.onIdle();
                }, this.idleTimeout);
            }
        }
    }
    class WeakDomRegistry {
        constructor() {
            this.keyToObjectMap = new Map(); // Maps strings to objects
            this.objectToDomMap = new WeakMap(); // Maps objects to DOM elements
        }
        set(id, element) {
            let keyObject = {};
            this.keyToObjectMap.set(id, keyObject);
            this.objectToDomMap.set(keyObject, element);
        }
        get(id) {
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
        delete(id) {
            let keyObject = this.keyToObjectMap.get(id);
            if (keyObject) {
                this.objectToDomMap.delete(keyObject);
                this.keyToObjectMap.delete(id);
            }
        }
        has(id) {
            return this.keyToObjectMap.has(id) && this.objectToDomMap.has(this.keyToObjectMap.get(id));
        }
    }
    function generateShortRandomHash(length = 6) {
        const chars = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
        let result = '';
        for (let i = 0; i < length; i++) {
            result += chars[Math.floor(Math.random() * chars.length)];
        }
        return result;
    }
    function isElementAttached(el) {
        return document.body.contains(el);
    }
    function isElementVisible(el) {
        let currentElement = el;
        let level = 0;
        // Check element style and its ancestors
        while (currentElement) {
            // Check if the element is within the viewport
            if (level === 0) {
                const rect = currentElement.getBoundingClientRect();
                // Check if the element is within the viewport
                if (rect.width <= 0 || rect.height <= 0) {
                    // DEBUG:
                    // console.log('level[' + level + '] -> size is 0');
                    return false;
                }
            }
            const style = getComputedStyle(currentElement);
            if (style.display === 'contents') {
                // If the element is a "contents" element, it doesn't enforce style, skip.
                currentElement = currentElement.parentElement;
                level++;
                continue;
            }
            if (style.display === 'none' || style.visibility === 'hidden' || parseFloat(style.opacity) === 0) {
                // If we need to debug why something is not visible.
                // DEBUG:
                // let reason = {
                //     display: style.display,
                //     visibility: style.visibility,
                //     opacity: style.opacity,
                //     width: style.width,
                //     height: style.height,
                // };
                // console.log(
                //     '[level ' + level + '] -> class: ' + classes + ', hidden ' + JSON.stringify(reason, null, 4),
                // );
                return false;
            }
            // Continue checking the parents to see if any of those impose visibility restrictions.
            currentElement = currentElement.parentElement;
            level++;
        }
        return true;
    }
    function qualifyElement(element, visible) {
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
    // Expose this directly.
    if (!window.SophiaJS) {
        window.SophiaJS = new SophiaPage();
    }
})();
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoic29waGlhLmpzIiwic291cmNlUm9vdCI6IiIsInNvdXJjZXMiOlsiLi4vc3JjL3NvcGhpYS50cyJdLCJuYW1lcyI6W10sIm1hcHBpbmdzIjoiO0FBQUEsQ0FBQztJQUNHLE1BQU0sVUFBVTtRQVlaO1lBWFEsb0JBQWUsR0FBRyxJQUFJLGVBQWUsRUFBRSxDQUFDO1lBRXhDLGVBQVUsR0FLZCxFQUFFLENBQUM7WUFFQyxzQkFBaUIsR0FBRyxJQUFJLHNCQUFzQixFQUFFLENBQUM7WUFHckQsT0FBTyxDQUFDLEdBQUcsQ0FBQywwQ0FBMEMsR0FBRyxNQUFNLENBQUMsUUFBUSxDQUFDLElBQUksQ0FBQyxDQUFDO1lBRS9FLG9DQUFvQztZQUNwQyxJQUFJLENBQUMsaUJBQWlCLEVBQUUsQ0FBQztZQUN6QixJQUFJLENBQUMsbUJBQW1CLEVBQUUsQ0FBQztZQUUzQixJQUFJLENBQUMscUJBQXFCLEVBQUUsQ0FBQztZQUM3QixJQUFJLENBQUMsZ0JBQWdCLEVBQUUsQ0FBQztZQUV4QixJQUFJLENBQUMscUJBQXFCLEVBQUUsQ0FBQztRQUNqQyxDQUFDO1FBRUQsQ0FBQyxDQUFDLFFBQWdCLEVBQUUsaUJBQTBCO1lBQzFDLElBQUksVUFBc0IsQ0FBQztZQUUzQixJQUFJLGlCQUFpQixFQUFFO2dCQUNuQixNQUFNLFFBQVEsR0FBRyxJQUFJLENBQUMsZUFBZSxDQUFDLEdBQUcsQ0FBQyxpQkFBaUIsQ0FBQyxDQUFDO2dCQUM3RCxVQUFVLEdBQUcsUUFBUSxJQUFJLFFBQVEsQ0FBQzthQUNyQztpQkFBTTtnQkFDSCxVQUFVLEdBQUcsUUFBUSxDQUFDO2FBQ3pCO1lBRUQsTUFBTSxFQUFFLEdBQUcsVUFBVSxDQUFDLGFBQWEsQ0FBQyxRQUFRLENBQUMsQ0FBQztZQUM5QyxJQUFJLEVBQUUsRUFBRTtnQkFDSixPQUFPLElBQUksQ0FBQyxVQUFVLENBQUMsRUFBaUIsQ0FBQyxDQUFDO2FBQzdDO2lCQUFNO2dCQUNILE9BQU8sSUFBSSxDQUFDO2FBQ2Y7UUFDTCxDQUFDO1FBRUQs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