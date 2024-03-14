"use strict";
(function () {
    class PipeablePage {
        constructor() {
            this.elementRegistry = new WeakDomRegistry();
            this.xhrHandles = {};
            this.neworkIdleMonitor = new NetworkActivityMonitor();
            console.log('PipeableJS constructor for frame with url ' + window.location.href);
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
            const pipeableEls = [];
            for (let i = 0; i < elements.length; i++) {
                const el = elements[i];
                pipeableEls.push(this.wrapHandle(el));
            }
            return pipeableEls;
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
            const pipeableEls = [];
            for (let i = 0; i < elements.snapshotLength; i++) {
                const el = elements.snapshotItem(i);
                if (el) {
                    pipeableEls.push(this.wrapHandle(el));
                }
            }
            return pipeableEls;
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
            const message = { ctx: 'pipeable', payload: { requestId: requestId } };
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
                        if (data.ctx === 'pipeable') {
                            // Forward message to native.
                            window.webkit.messageHandlers.handler.postMessage({
                                ctx: 'pipeable',
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
                        if (data.ctx === 'pipeable') {
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
                console.log('PipeableJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
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
                console.log('PipeableJS load event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
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
                console.log('PipeableJS networkidle event for frame with url ' + window.location.href);
                const message = {
                    ctx: 'pipeable',
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
    if (!window.PipeableJS) {
        window.PipeableJS = new PipeablePage();
    }
})();
//# sourceMappingURL=data:application/json;base64,eyJ2ZXJzaW9uIjozLCJmaWxlIjoicGlwZWFibGUuanMiLCJzb3VyY2VSb290IjoiIiwic291cmNlcyI6WyIuLi9zcmMvcGlwZWFibGUudHMiXSwibmFtZXMiOltdLCJtYXBwaW5ncyI6IjtBQUFBLENBQUM7SUFDRyxNQUFNLFlBQVk7UUFZZDtZQVhRLG9CQUFlLEdBQUcsSUFBSSxlQUFlLEVBQUUsQ0FBQztZQUV4QyxlQUFVLEdBS2QsRUFBRSxDQUFDO1lBRUMsc0JBQWlCLEdBQUcsSUFBSSxzQkFBc0IsRUFBRSxDQUFDO1lBR3JELE9BQU8sQ0FBQyxHQUFHLENBQUMsNENBQTRDLEdBQUcsTUFBTSxDQUFDLFFBQVEsQ0FBQyxJQUFJLENBQUMsQ0FBQztZQUVqRixvQ0FBb0M7WUFDcEMsSUFBSSxDQUFDLGlCQUFpQixFQUFFLENBQUM7WUFDekIsSUFBSSxDQUFDLG1CQUFtQixFQUFFLENBQUM7WUFFM0IsSUFBSSxDQUFDLHFCQUFxQixFQUFFLENBQUM7WUFDN0IsSUFBSSxDQUFDLGdCQUFnQixFQUFFLENBQUM7WUFFeEIsSUFBSSxDQUFDLHFCQUFxQixFQUFFLENBQUM7UUFDakMsQ0FBQztRQUVELENBQUMsQ0FBQyxRQUFnQixFQUFFLGlCQUEwQjtZQUMxQyxJQUFJLFVBQXNCLENBQUM7WUFFM0IsSUFBSSxpQkFBaUIsRUFBRTtnQkFDbkIsTUFBTSxRQUFRLEdBQUcsSUFBSSxDQUFDLGVBQWUsQ0FBQyxHQUFHLENBQUMsaUJBQWlCLENBQUMsQ0FBQztnQkFDN0QsVUFBVSxHQUFHLFFBQVEsSUFBSSxRQUFRLENBQUM7YUFDckM7aUJBQU07Z0JBQ0gsVUFBVSxHQUFHLFFBQVEsQ0FBQzthQUN6QjtZQUVELE1BQU0sRUFBRSxHQUFHLFVBQVUsQ0FBQyxhQUFhLENBQUMsUUFBUSxDQUFDLENBQUM7WUFDOUMsSUFBSSxFQUFFLEVBQUU7Z0JBQ0osT0FBTyxJQUFJLENBQUMsVUFBVSxDQUFDLEVBQWlCLENBQUMsQ0FBQzthQUM3QztpQkFBTTtnQkFDSCxPQUFPLElBQUksQ0FBQzthQUNmO1FBQ0wsQ0FBQztR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