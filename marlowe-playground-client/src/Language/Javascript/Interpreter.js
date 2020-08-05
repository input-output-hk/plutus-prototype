/*eslint-env node*/
'use strict';
const safeEval = require('notevil')

exports.eval_ = function (left, right, javascript) {
  // include any libraries etc we want by providing a context. be careful!
  // here we can pass in our library for constructing contracts
  const context = { JSON: JSON }
  try {
    let res = safeEval(javascript, context);
    return right(res);
  } catch (error) {
    return (left(error.toString()));
  }
}